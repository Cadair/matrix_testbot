#!/bin/env xonsh
import time
from pathlib import Path
from urllib.parse import quote

import yaml
import requests

MATRIX_API = "http://localhost:8008/_matrix/client/r0"

admin_user = admin_password = $(whoami).strip()


"""
Functions
"""

def get_or_create_room(name, room_alias):
    room_alias_name = room_alias[1:].split(":")[0]
    resp = requests.get(f"{MATRIX_API}/directory/room/"+quote(room_alias), params={"access_token":access_token})
    if resp.ok:
        room_id = resp.json()["room_id"]
    else:
        resp = requests.post(f"{MATRIX_API}/createRoom",
                             json={"preset": "public_chat",
                                   "room_alias_name":room_alias_name,
                                   "name": name},
                             params={"access_token":access_token}).json()
        print(resp)
        room_id = resp["room_id"]
    return room_id

def register_user(username, password):
    session = requests.post(f"{MATRIX_API}/register?kind=user", json={"username": username}).json()
    if session.get("errcode", None):
        if session["errcode"] == "M_USER_IN_USE":
            return username
    print(session)
    session = session["session"]
    resp = requests.post(f"{MATRIX_API}/register?kind=user",
                         json={"username": username,
                               "password": password,
                               "auth":{"session": session,
                                       "type": "m.login.dummy"}})
    return resp.json().get("access_token", username)



"""
Parse the opsdroid config.
"""
with open("configuration.yaml") as f:
    opsdroid = yaml.safe_load(f.read())
matrix = list(filter(lambda conn: conn["name"] == "matrix", opsdroid["connectors"]))[0]

if matrix["homeserver"] != "http://localhost:8008":
    raise ValueError("For this script to work opsdroid must be configured with a local homeserver, with the url http://localhost:8008")


user_mxid = matrix["mxid"]
username = user_mxid.split("@")[1].split(":")[0]
password = matrix["password"]
server_name = user_mxid.split(":")[1]

if "rooms" in matrix:
    rooms = matrix["rooms"]
elif "room" in matrix:
    rooms = {"main": matrix["room"]}
else:
    raise ValueError("Can not parse rooms in config")


"""
Start and configure synapse using docker.
"""
$(mkdir -p synapse)

synapse_path = Path("./synapse").absolute()

docker rm synapse_conf

if not (synapse_path / "homeserver.yaml").exists():
    $[docker run --name synapse_conf -v @(f"{synapse_path}:/data") -e @("MATRIX_UID="+$(id -u).strip()) -e @(f"SERVER_NAME={server_name}") -e REPORT_STATS=no avhost/docker-matrix:latest]
    print("Changing ownership of config directory...")
    sudo chown -R @($(whoami).strip()) @(synapse_path)

print("Removing old container...")
docker stop synapse
docker rm synapse

print("Enabling registration...")
sed -i "s/enable_registration: False/enable_registration: true/" @(synapse_path/"homeserver.yaml")
print("Starting Synapse...")
docker run -d --name synapse -v @(f"{synapse_path}:/data") -p 8008:8008 -e @("MATRIX_UID="+$(id -u).strip()) -e @(f"SERVER_NAME={server_name}") -e REPORT_STATS=no avhost/docker-matrix:latest

# Wait for synapse to spin up
print("Waiting for synapse to start...")
for i in range(50):
    try:
        resp = requests.get(f"{MATRIX_API[:-3]}/versions")
        if resp.ok:
            break
    except requests.exceptions.ConnectionError:
        pass
    time.sleep(0.5)

"""
Register users and create rooms.
"""

print(f"Register user {admin_user} with password {admin_password}")
reg = register_user(admin_user, admin_password)

print("Registering bot user...")
reg = register_user(username, password)
if reg != username:
    print(f"{username} registered")
    access_token = reg
else:
    access_token = requests.post(f"{MATRIX_API}/login", json={"type":"m.login.password", "identifier":{"type": "m.id.user", "user":username}, "password":password}).json()["access_token"]


print("Creating rooms...")
room_ids = {name: get_or_create_room(name, room_alias) for name, room_alias in rooms.items()}
print(room_ids)


print("Inviting Admin user...")
for room_id in room_ids.values():
    resp = requests.post(f"{MATRIX_API}/rooms/{room_id}/invite", json={"user_id": f"@{admin_user}:localhost"}, params={"access_token":access_token, "room_id":room_id})
