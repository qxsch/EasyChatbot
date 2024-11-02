from datetime import datetime, timedelta
import json, io
from flask import Flask, render_template, request, jsonify, redirect, url_for, send_file
from . import app, all_users, ChatbotUser
from flask_login import login_user, login_required, logout_user, current_user
from .easy_chat import EasyChatClient, dict_to_chat_messages
from .azurestorage import BlobStorage


chatClient = EasyChatClient()


#region -------- WEB/UI ENDPOINTS --------
@app.route("/")
def home():
    # if the user is not logged in, redirect to the login page
    if not current_user.is_authenticated:
        return redirect(url_for("login"))
    if not isinstance(current_user, ChatbotUser):
        return redirect(url_for("login"))
    return render_template("index.html", user=current_user)


@app.route("/logout")
def logout():
    logout_user()
    return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    # post request? process the login form
    if request.method == "POST":
        # user exists?
        username = str(request.form.get("username")).lower().strip()
        if username not in all_users:
            return render_template("login.html", message="User not found", user=current_user)
        user = all_users[username]
        # Check the username (again)
        if str(user.username).lower().strip() != username:
            return render_template("login.html", message="Invalid credentials", user=current_user)
        # Check the password
        if user.password == request.form.get("password"):
            # Use the login_user method to log in the user
            login_user(user)
            return redirect(url_for("home"))
        return render_template("login.html", message="Invalid credentials", user=current_user)
    return render_template("login.html", user=current_user)
#endregion -------- WEB/UI ENDPOINTS --------

#region -------- API ENDPOINTS --------
@login_required
@app.route("/api/chat", methods=["POST"])
def api_chat():
    if not isinstance(current_user, ChatbotUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["admin", "user"]:
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        return jsonify(chatClient.chat(dict_to_chat_messages(request.get_json()))), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@login_required
@app.route("/api/blobstorage/file", methods=["GET"])
def api_blobstorage_pdf():
    if not isinstance(current_user, ChatbotUser):
        logout_user()
        return redirect(url_for("login"))
    if current_user.role not in ["admin", "user"]:
        return jsonify({"success": False, "error": "Unauthorized"}), 403
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


