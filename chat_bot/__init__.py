from flask import Flask  # Import the Flask class
import os
app = Flask(__name__)    # Create an instance of the class for our use
app.config['MAX_CONTENT_LENGTH'] = 64 * 1000 * 1000

from .iam import all_defined_users
from flask_login import LoginManager, UserMixin
login_manager = LoginManager()
login_manager.init_app(app)


app.secret_key = os.getenv("CHATBOT_SECRET_KEY", "superSecretKey")
app.config['SESSION_TYPE'] = 'filesystem'




@login_manager.user_loader
def loader_user(user_id):
    if user_id in all_defined_users:
        return all_defined_users[user_id]
    return None
