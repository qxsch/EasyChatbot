import os
from typing import Union
from flask_login import LoginManager, UserMixin


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

# create the users
all_defined_users = create_all_users()

