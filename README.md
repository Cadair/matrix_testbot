# A Matrix Opsdroid tester

The `./start_synapse.xsh` [xonsh](xon.sh) script in this repo will start (using
docker) a synapse instance with the correct configuration to test your opsdroid
bot.

Two user accounts will be registered on the synapse server, one for you, which
will use your computer username as the username and password. One will be read
from the opsdroid config for the bot account.

All the rooms configured in the opsdroid will be created and your user will be
invited to them.


## Requirements

* requests
* pyyaml
* docker
