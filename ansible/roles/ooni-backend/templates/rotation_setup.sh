#!/bin/bash
# Managed by ansible, see roles/ooni-backend/tasks/main.yml
#
# Configure test-helper droplet
# This script is run remotely on newly spawned VM by https://github.com/ooni/backend/blob/master/analysis/rotation.py
# It runs as root and with CWD=/
#
set -euo pipefail
exec 1>/var/log/vm_rotation_setup.log 2>&1
echo > /etc/motd

echo "Configuring APT"
echo "deb [trusted=yes] https://ooni-internal-deb.s3.eu-central-1.amazonaws.com unstable main" > /etc/apt/sources.list.d/ooni.list
cat <<EOF  | gpg --dearmor > /etc/apt/trusted.gpg.d/ooni.gpg
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEYGISFRYJKwYBBAHaRw8BAQdA4VxoR0gSsH56BbVqYdK9HNQ0Dj2YFVbvKIIZ
JKlaW920Mk9PTkkgcGFja2FnZSBzaWduaW5nIDxjb250YWN0QG9wZW5vYnNlcnZh
dG9yeS5vcmc+iJYEExYIAD4WIQS1oI8BeW5/UhhhtEk3LR/ycfLdUAUCYGISFQIb
AwUJJZgGAAULCQgHAgYVCgkICwIEFgIDAQIeAQIXgAAKCRA3LR/ycfLdUFk+AQCb
gsUQsAQGxUFvxk1XQ4RgEoh7wy2yTuK8ZCkSHJ0HWwD/f2OAjDigGq07uJPYw7Uo
Ih9+mJ/ubwiPMzUWF6RSdgu4OARgYhIVEgorBgEEAZdVAQUBAQdAx4p1KerwcIhX
HfM9LbN6Gi7z9j4/12JKYOvr0d0yC30DAQgHiH4EGBYIACYWIQS1oI8BeW5/Uhhh
tEk3LR/ycfLdUAUCYGISFQIbDAUJJZgGAAAKCRA3LR/ycfLdUL4cAQCs53fLphhy
6JMwVhRs02LXi1lntUtw1c+EMn6t7XNM6gD+PXpbgSZwoV3ZViLqr58o9fZQtV3s
oN7jfdbznrWVigE=
=PtYb
-----END PGP PUBLIC KEY BLOCK-----
EOF

# Vector
cat <<EOF  | gpg --dearmor > /etc/apt/trusted.gpg.d/vector.gpg
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2

mQENBF9gFZ0BCADETtIHM8y5ehMoyNiZcriK+tHXyKnbZCKtMCKcC4ll94/6pekQ
jKIPWg8OXojkCtwua/TsddtQmOhUxAUtv6K0jO8r6sJ8rezMhuNH8J8rMqWgzv9d
2+U7Z7GFgcP0OeD+KigtnR8uyp50suBmEDC8YytmmbESmG261Y38vZME0VvQ+CMy
Yi/FvKXBXugaiCtaz0a5jVE86qSZbKbuaTHGiLn05xjTqc4FfyP4fi4oT2r6GGyL
Bn5ob84OjXLQwfbZIIrNFR10BvL2SRLL0kKKVlMBBADodtkdwaTt0pGuyEJ+gVBz
629PZBtSrwVRU399jGSfsxoiLca9//c7OJzHABEBAAG0OkNsb3Vkc21pdGggUGFj
a2FnZSAodGltYmVyL3ZlY3RvcikgPHN1cHBvcnRAY2xvdWRzbWl0aC5pbz6JATcE
EwEIACEFAl9gFZ0CGy8FCwkIBwMFFQoJCAsFFgIDAQACHgECF4AACgkQNUPbLQor
xLhf6gf8DyfIpKjvEeW/O8lRUTpkiPKezJbb+udZboCXJKDD02Q9PE3hfEfQRr5X
muytL7YMPvzqBVuP3xV5CN3zvtiQQbZiDhstImVyd+t24pQTkjzkvy+A2yvUuIkE
RWxuey41f5FNj/7wdfJnHoU9uJ/lvsb7DLXw7FBMZFNBR6LED/d+b61zMzVvmFZA
gsrCGwr/jfySwnpShmKdJaMTHQx0qt2RfXwNm2V6i900tAuMUWnmUIz5/9vENPKm
0+31I43a/QgmIrKEePhwn2jfA1oRlYzdv+PbblSTfjTStem+GqQkj9bZsAuqVH8g
3vq0NvX0k2CLi/W9mTiSdHXFChI15A==
=k36w
-----END PGP PUBLIC KEY BLOCK-----
EOF

echo "deb https://repositories.timber.io/public/vector/deb/debian bullseye main" > /etc/apt/sources.list.d/vector.list

echo "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get purge -qy unattended-upgrades rsyslog
apt-get upgrade -qy
apt-get install -qy --no-install-recommends chrony netdata oohelperd netdata-plugins-python

systemctl daemon-reload
systemctl restart systemd-journald.service
logger start
systemctl restart systemd-journald.service

apt-get install -qy --no-install-recommends vector

echo "Configuring Vector"
# The certs are copied over by rotation.py
cat > /etc/vector/vector.toml <<EOF
[sources.local_journald]
type = "journald"

[sinks.monitoring_ooni_org]
type = "vector"
inputs = [ "local_journald" ]
address = "monitoring.ooni.org:10514"
compression = true

tls.enabled = true
tls.verify_certificate = true
tls.verify_hostname = false
tls.ca_file = "/etc/vector/oonicacert.pem"
tls.crt_file = "/etc/vector/node-cert.pem"
tls.key_file = "/etc/vector/node.key"
EOF

echo "Enabling incoming connections to Netdata"
cat > /etc/netdata/netdata.conf <<EOF
[global]
	run as user = netdata
	web files owner = root
	web files group = root
	# Netdata is not designed to be exposed to potentially hostile
	# networks. See https://github.com/netdata/netdata/issues/164
	bind socket to IP = 0.0.0.0
[web]
	allow connections from = 5.9.112.244
EOF

echo "Enabling chrony monitoring and restart Netdata"
sed -i 's/^chrony: no/chrony: yes/g' /usr/lib/netdata/conf.d/python.d.conf

echo "Installing Nginx"
apt-get install -qy nginx-light

# Netdata will be [re]started by rotation.py after configuring and restarting Nginx

# Used by https://github.com/ooni/pipeline/blob/master/af/analysis/rotation.py
# to detect when the new test helper is ready to be used
echo "Rotation setup completed"
echo "Flag file generated by rotation_setup.sh" > /var/run/rotation_setup_completed
