from datetime import datetime, timedelta
import json, io, hashlib, os
from flask import Flask, render_template, request, jsonify, redirect, url_for, send_file, stream_with_context, Response
from . import app, all_defined_users
from .iam import ChatbotUser, iam_login_required, iam_get_current_user, iam_is_authenticated, USE_AUTH_TYPE
from flask_login import login_user, logout_user
from .easy_chat import EasyChatClient, dict_to_chat_messages
from .azurestorage import BlobStorage

chatClient = EasyChatClient()
# get the path of the current script
try:
    systemPromptFewshotPath = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "system-prompt-fewshot-examples.md")
    systemPromptPath = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "system-prompt.md")
    systemPrompt = ""
    systemPromptFewshot = ""
    if os.path.exists(systemPromptPath):
        with open(systemPromptPath, "r") as f:
            systemPrompt = f.read()
        systemPrompt = systemPrompt.strip()
        if systemPrompt != "":
            chatClient.setSystemMessage(systemPrompt)
    if os.path.exists(systemPromptFewshotPath):
        with open(systemPromptFewshotPath, "r") as f:
            systemPromptFewshot = f.read()
        systemPromptFewshot = systemPromptFewshot.strip()
        if systemPromptFewshot != "":
            chatClient.setFewShotExamples([systemPromptFewshot])
except:
    pass


def getChatbotConfig() -> dict:
    c = {
        "streaming": os.getenv("CHATBOT_STREAMING")
    }
    if c["streaming"] is None:
        c["streaming"] = True
    elif c["streaming"].lower() in [ "false", "off", "no", "disabled", "disable" ]:
        c["streaming"] = False
    else:
        c["streaming"] = True
    return c


#region -------- WEB/UI ENDPOINTS --------
@app.route("/")
def home():
    # if the user is not logged in, redirect to the login page
    if not iam_is_authenticated():
        return redirect(url_for("login"))
    return render_template("index.html", user=iam_get_current_user(), chatbot_config=getChatbotConfig())


@app.route("/logout")
def logout():
    if USE_AUTH_TYPE == "aad":
        return redirect('/.auth/logout')
    logout_user()
    return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    if USE_AUTH_TYPE == "aad":
        return redirect('/.auth/login/aad')
    # post request? process the login form
    if request.method == "POST":
        # user exists?
        username = str(request.form.get("username")).lower().strip()
        if username not in all_defined_users:
            return render_template("login.html", message="User not found", user=iam_get_current_user())
        user = all_defined_users[username]
        # Check the username (again)
        if str(user.username).lower().strip() != username:
            return render_template("login.html", message="Invalid credentials", user=iam_get_current_user())
        # Check the password
        try:
            hashed_password = hashlib.sha256(request.form.get("password").encode()).hexdigest()
        except:
            hashed_password = ""
        if user.password[:7] == "sha256:" and user.password[7:] == hashed_password:
            # Use the login_user method to log in the user
            login_user(user)
            return redirect(url_for("home"))
        if user.password[:7] != "sha256:" and user.password == request.form.get("password"):
            # Use the login_user method to log in the user
            login_user(user)
            return redirect(url_for("home"))
        return render_template("login.html", message="Invalid credentials", user=iam_get_current_user())
    return render_template("login.html", user=iam_get_current_user())
#endregion -------- WEB/UI ENDPOINTS --------

#region -------- API ENDPOINTS --------
@iam_login_required
@app.route("/api/chat", methods=["POST"])
def api_chat():
    user = iam_get_current_user()
    if user is None:
        return jsonify({"success": False, "error": "Not logged in"}), 404
    try:
        bs = BlobStorage()
        chatClient.setSearchFilterFromRole(user.getRole(), bs.getBaseUrl())
        return jsonify(
            chatClient.chat(
                dict_to_chat_messages(request.get_json())
            )
        ), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@iam_login_required
@app.route("/api/chat/stream", methods=["POST"])
def api_chat_stream():
    user = iam_get_current_user()
    if user is None:
        return jsonify({"success": False, "error": "Not logged in"}), 404
    try:
        bs = BlobStorage()
        chatClient.setSearchFilterFromRole(user.getRole(), bs.getBaseUrl())
        return Response(
            stream_with_context(
                chatClient.streamedChat(
                    dict_to_chat_messages(request.get_json()),
                    outputFormat = "json"
                )
            ),
            200,
            content_type="application/json"
        )
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@iam_login_required
@app.route("/api/blobstorage/file", methods=["GET"])
def api_blobstorage_pdf():
    # check for required parameters
    if not request.args.get("storageaccount_name") or not request.args.get("storageaccount_container") or not request.args.get("storageaccount_blob"):
        return jsonify({"success": False, "error": "Missing parameters"}), 400
    # check for supported file type
    fileExtension = str(request.args.get("storageaccount_blob")).split(".")[-1]
    mimetype = "application/octet-stream"
    if fileExtension == "pdf":
        mimetype = "application/pdf"
    else:
        return jsonify({"success": False, "error": "Invalid file type"}), 406
    bs = BlobStorage()
    if not bs.hasFullPath(
        account_name = request.args.get("storageaccount_name"),
        container_name = request.args.get("storageaccount_container"),
        path = request.args.get("storageaccount_blob")
    ):
        return jsonify({"success": False, "error": "Pdf document does not exist"}), 404
    # send the file
    return send_file(
        io.BytesIO(bs.downloadBinary(request.args.get("storageaccount_blob"))),
        mimetype = mimetype,
        as_attachment = True,
        download_name = str(request.args.get("storageaccount_blob")).split("/")[-1]
    ), 200
#endregion -------- API ENDPOINTS --------


