import os, base64, json
from typing import Union
from flask_login import LoginManager, UserMixin, current_user, logout_user
from flask import request, current_app, redirect, url_for
from functools import wraps



USE_AUTH_TYPE= os.environ.get("USE_AUTH_TYPE", "local").lower().strip()
# synonyms for aad
if USE_AUTH_TYPE == "entra" or USE_AUTH_TYPE == "entraid":
    USE_AUTH_TYPE = "aad"
# just allow local or aad -> default to local
if USE_AUTH_TYPE != "local" and USE_AUTH_TYPE != "aad":
    USE_AUTH_TYPE = "local"



class ChatbotRole:
    _name : str
    _description : str = ""
    _filter : Union[None, str] = None
    _blobPathStartsWith : Union[None, str] = None

    def __init__(self, name : str, description : str, filter : Union[None, str] = None, blobPathStartsWith : Union[None, str] = None):
        self._name = str(name)
        self._description = str(description)
        if not (filter is None):
            self._filter = str(filter)
        if not (blobPathStartsWith is None):
            self._blobPathStartsWith = str(blobPathStartsWith)

    def getName(self) -> str:
        return self._name
    def getDescription(self) -> str:
        return self._description
    def getFilter(self) -> Union[None, str]:
        return self._filter
    def getBlobPathStartsWith(self) -> Union[None, str]:
        return self._blobPathStartsWith


class ChatbotUser(UserMixin):
    id = ""
    username = ""
    password = ""
    role = ""
    def __init__(self, username : str, password : str, role : str):
        self.username = str(username).lower().strip()
        self.password = str(password)
        self.role = str(role).lower().strip()
        self.id = str(username).lower().strip()

    def getRole(self) -> ChatbotRole:
        return all_defined_roles.get(self.role, all_defined_roles["user"])

def create_all_roles():
    allRoles = { }
    # get the directory of the current script
    roleJson = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "roles.json")
    if os.path.exists(roleJson):
        import json
        with open(roleJson, "r") as f:
            for r in json.load(f):
                if "role" in r and r["role"] != "":
                    k = str(r["role"]).lower().strip()
                    if k in allRoles:
                        continue
                    allRoles[k] = ChatbotRole(
                        r["role"],
                        r.get("description", ""),
                        r.get("filter", None),
                        r.get("blobPathStartsWith", None)
                    )
    if "user" not in allRoles:
        allRoles["user"] = ChatbotRole("user", "User role")
    return allRoles

# create the roles
all_defined_roles = create_all_roles()

def create_all_users():
    allUsers = { }
    # get the directory of the current script
    userJson = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "users.json")
    if os.path.exists(userJson):
        import json
        with open(userJson, "r") as f:
            for usr in json.load(f):
                if "username" in usr and "password" in usr and "role" in usr:
                    role = str(usr["role"]).lower().strip()
                    if role not in all_defined_roles:
                        role = "user"
                    print(f"Adding user {usr['username']} with role {role}")
                    allUsers[str(usr["username"]).lower().strip()] = ChatbotUser(
                        str(usr["username"]),
                        str(usr["password"]),
                        role
                    )
    # do not load the default users from the enviornment, if the user.json file exists
    if len(allUsers) > 0:
        return allUsers
    # TODO: integrate with entra id
    return allUsers

# create the users in case of local auth
if USE_AUTH_TYPE == "local":
    all_defined_users = create_all_users()
else:
    all_defined_users = { }




class EntraEasyAuthInfo:
    _authInfo = None
    _groups = []
    _username = ""
    _userId = ""
    _authenticated = False

    def __init__(self, headers : dict):
        if "x-ms-client-principal" in headers:
            try:
                self._authInfo = json.loads(base64.b64decode(headers["x-ms-client-principal"]).decode("utf-8"))
            except:
                self._authInfo = None
        self._authInfo = json.loads(base64.b64decode(headers["x-ms-client-principal"]).decode("utf-8"))

        self._groups = []
        self._username = ""
        self._userId = ""
        self._authenticated = False

        if not (self._authInfo is None) and "auth_typ" in self._authInfo and self._authInfo["auth_typ"] == "aad" and "claims" in self._authInfo:
            for c in self._authInfo['claims']:
                if c["typ"] == "groups":
                    self._groups.append(c["val"])
                if c["typ"] == "preferred_username":
                    self._username = c["val"]
                if c["typ"] == "http://schemas.microsoft.com/identity/claims/objectidentifier":
                    self._userId = c["val"]
        if self._username != "" and self._userId != "":
            self._authenticated = True

    def getUserId(self):
        try:
            return str(self._userId)
        except:
            return ""
    def getUserName(self):
        try:
            return str(self._username)
        except:
            return ""
    def getGroups(self):
        try:
            return self._groups
        except:
            return [ ]
        
    def isAuthenticated(self):
        return self._authenticated


def iam_is_authenticated() -> bool:
    if USE_AUTH_TYPE == "local":
        if not isinstance(current_user, ChatbotUser):
            return False
        return current_user.is_authenticated
    elif USE_AUTH_TYPE == "aad":
        u = iam_get_current_user()
        if u is None:
            return False
        return u.is_authenticated
    return False


def iam_get_current_user() -> Union[None, ChatbotUser]:
    if USE_AUTH_TYPE == "local":
        if not isinstance(current_user, ChatbotUser):
            return None
        else:
            return current_user
    elif USE_AUTH_TYPE == "aad":
        auth = EntraEasyAuthInfo(request.headers)
        if auth.isAuthenticated():
            role = "user"
            for r in auth.getGroups():
                if r in all_defined_roles:
                    role = r
                    break
            u = ChatbotUser(auth.getUserName(), "", role)
            return u
    return None




def iam_login_required(func):
    @wraps(func)
    def decorated_view(*args, **kwargs):
        if request.method in [ "OPTIONS" ]:
            pass
        else:
            if not iam_is_authenticated():
                return redirect(url_for("login"))
        return func(*args, **kwargs)

    return decorated_view

