# The reMarkable over USB: the `remarkable` alias in ~/.ssh/config (root@10.11.99.1).
host := "remarkable"
key := home_directory() / ".ssh/id_rsa_remarkable"

# Reinstall, restart, and persist the remap daemon after a reMarkable OS update
refresh:
    #!/usr/bin/env bash
    set -euo pipefail
    # build.sh calls plain ssh/scp, so the key has to come from the agent.
    ssh-add -T {{key}}.pub 2>/dev/null || ssh-add {{key}}
    if ! ssh -o ConnectTimeout=5 {{host}} true; then
      echo "can't reach {{host}} -- is the reMarkable plugged in over USB and awake?" >&2
      exit 1
    fi
    RM_HOST={{host}} ./build.sh
