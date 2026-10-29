# Container example

Puts one Debian 13 container on a node that [examples/single-node](../single-node) set up, with OpenTofu's [bpg/proxmox](https://registry.opentofu.org/providers/bpg/proxmox) provider. Conn3x configures the host; the provider then manages what runs on it through the Proxmox API, in the same tool and the same workflow.

Make an API token on the node first. `--privsep 0` gives the token root's permissions:

```sh
ssh root@203.0.113.10 pveum user token add root@pam tofu --privsep 0
```

Pass the token as `root@pam!tofu=` followed by the `value` it printed:

```sh
export TF_VAR_api_token='root@pam!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
conn3x init
conn3x apply -var address=203.0.113.10
```

It adds a storage directory, `guests`, at `/var/lib/guests`, downloads Proxmox's Debian 13 container template into it, and starts container 100, `hello`. Then:

```sh
ssh root@203.0.113.10 pct exec 100 -- cat /etc/os-release
```

The container has no network, since the node has no bridge for it yet; see "What it doesn't do" in the [circuit's README](../../README.md). `conn3x destroy` removes the container, the template and the storage. Delete the token with `pveum user token remove root@pam tofu`.
