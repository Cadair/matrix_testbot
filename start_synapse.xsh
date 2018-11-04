#!/bin/env xonsh
admin_user = admin_password = $(whoami).strip()

import time
import requests

from pathlib import Path
from urllib.parse import quote

$(mkdir -p synapse)

synapse_path = Path("./synapse").absolute()

docker rm synapse_conf

if not (synapse_path / "homeserver.yaml").exists():
    $[docker run --name synapse_conf -v @(f"{synapse_path}:/data") -e @("MATRIX_UID="+$(id -u).strip()) -e SERVER_NAME=localhost -e REPORT_STATS=no avhost/docker-matrix:latest]
    sudo chown -R @($(whoami).strip()) @(synapse_path)


docker stop synapse
docker rm synapse

sed -i "s/enable_registration: False/enable_registration: true/" @(synapse_path/"homeserver.yaml")
docker run -d --name synapse -v @(f"{synapse_path}:/data") -p 8008:8008 -e @("MATRIX_UID="+$(id -u).strip()) -e SERVER_NAME=localhost -e REPORT_STATS=no avhost/docker-matrix:latest

time.sleep(5)
def register_user(username, password):
    session = requests.post("http://localhost:8008/_matrix/client/r0/register?kind=user", json={"username": username}).json()
    if session.get("errcode", None):
        if session["errcode"] == "M_USER_IN_USE":
            return username
    session = session["session"]
    resp = requests.post("http://localhost:8008/_matrix/client/r0/register?kind=user", json={"username": username, "password": password, "auth":{"session": session, "type": "m.login.dummy"}})
    return resp.json().get("access_token", username)


reg = register_user(admin_user, admin_password)


username = $ARGS[1]
reg = register_user($ARGS[1], $ARGS[2])
if reg != username:
    print(f"{username} registered")
    access_token = reg
else:
    access_token = requests.post("http://localhost:8008/_matrix/client/r0/login", json={"type":"m.login.password", "identifier":{"type": "m.id.user", "user":username}, "password":$ARGS[2]}).json()["access_token"]


resp = requests.get("http://localhost:8008/_matrix/client/r0/directory/room/"+quote("#bottest:localhost"), params={"access_token":access_token})
if resp.ok:
    room_id = resp.json()["room_id"]
else:
    resp = requests.post("http://localhost:8008/_matrix/client/r0/createroom", json={"preset": "public_chat", "room_alias_name":"bottest", "name": "bot test"}, params={"access_token":access_token})

resp = requests.post(f"http://localhost:8008/_matrix/client/r0/rooms/{room_id}/invite", json={"user_id": f"@{admin_user}:localhost"}, params={"access_token":access_token, "room_id":room_id})
print(resp, resp.json())

