#!/bin/sh -e

### ngrok section

if [ -n "$@" ]; then
  exec "$@"
fi

# Legacy compatible:
if [ -z "$NGROK_PORT" ]; then
	if [ -n "$HTTPS_PORT" ]; then
    	NGROK_PORT="$HTTPS_PORT"
	elif [ -n "$HTTPS_PORT" ]; then
		NGROK_PORT="$HTTP_PORT"
	elif [ -n "$APP_PORT" ]; then
		NGROK_PORT="$APP_PORT"
	fi
fi

ARGS="ngrok"

# Set the protocol.
if [ "$NGROK_PROTOCOL" = "TCP" ]; then
	ARGS="$ARGS tcp"
elif [ "$NGROK_PROTOCOL" = "TLS" ]; then
	ARGS="$ARGS tls"
	NGROK_PORT="${NGROK_PORT:-443}"
else
	ARGS="$ARGS http"
	NGROK_PORT="${NGROK_PORT:-80}"
fi

# Set the TLS binding flag
if [ -n "$NGROK_BINDTLS" ]; then
	ARGS="$ARGS -bind-tls=$NGROK_BINDTLS "
fi

# Set the authorization token.
if [ -n "$NGROK_AUTH" ]; then
	echo -e "\nauthtoken: $NGROK_AUTH" >> $HOME/.ngrok2/ngrok.yml
fi

# Set the subdomain or hostname, depending on which is set
if [ -n "$NGROK_HOSTNAME" ] && [ -n "$NGROK_AUTH" ]; then
	ARGS="$ARGS -hostname=$NGROK_HOSTNAME "
elif [ -n "$NGROK_SUBDOMAIN" ] && [ -n "$NGROK_AUTH" ]; then
	ARGS="$ARGS -subdomain=$NGROK_SUBDOMAIN "
elif [ -n "$NGROK_HOSTNAME" ] || [ -n "$NGROK_SUBDOMAIN" ]; then
	if [ -z "$NGROK_AUTH" ]; then
    	echo "You must specify an authentication token after registering at https://ngrok.com to use custom domains."
    	exit 1
	fi
fi

# Set the remote-addr if specified
if [ -n "$NGROK_REMOTE_ADDR" ]; then
	if [ -z "$NGROK_AUTH" ]; then
    	echo "You must specify an authentication token after registering at https://ngrok.com to use reserved ip addresses."
		exit 1
	fi
	ARGS="$ARGS -remote-addr=$NGROK_REMOTE_ADDR "
fi

# Set a custom region
if [ -n "$NGROK_REGION" ]; then
	ARGS="$ARGS -region=$NGROK_REGION "
fi

if [ -n "$NGROK_HEADER" ]; then
	ARGS="$ARGS -host-header=$NGROK_HEADER "
fi

if [ -n "$NGROK_USERNAME" ] && [ -n "$NGROK_PASSWORD" ] && [ -n "$NGROK_AUTH" ]; then
	ARGS="$ARGS -auth=$NGROK_USERNAME:$NGROK_PASSWORD "
elif [ -n "$NGROK_USERNAME" ] || [ -n "$NGROK_PASSWORD" ]; then
	if [ -z "$NGROK_AUTH" ]; then
    	echo "You must specify a username, password, and Ngrok authentication token to use the custom HTTP authentication."
    	echo "Sign up for an authentication token at https://ngrok.com"
    	exit 1
	fi
fi

if [ -n "$NGROK_DEBUG" ]; then
	ARGS="$ARGS -log stdout"
fi

# Set the port.
if [ -z "$NGROK_PORT" ]; then
	echo "You must specify a NGROK_PORT to expose."
	exit 1
fi

if [ -n "$NGROK_LOOK_DOMAIN" ]; then
	ARGS="$ARGS `echo $NGROK_LOOK_DOMAIN:$NGROK_PORT | sed 's|^tcp://||'`"
else
	ARGS="$ARGS `echo $NGROK_PORT | sed 's|^tcp://||'`"
fi

exec $ARGS

### certbot section
if [[ -z $EMAIL || -z $DOMAINS || -z $SECRET ]]; then
	echo "EMAIL, DOMAINS, and SECRET env vars required"
	env
	exit 1
fi

echo "Inputs:"
echo "  EMAIL: $EMAIL"
echo "  DOMAINS: $DOMAINS"
echo "  SECRET: $SECRET"

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
echo "Current Kubernetes namespace: $NAMESPACE"

echo "Starting HTTP server..."
python -m SimpleHTTPServer 80 &
PID=$!
echo "Starting certbot..."
certbot certonly --webroot -w $HOME -n --agree-tos --email ${EMAIL} --no-self-upgrade -d ${DOMAINS}
kill $PID
echo "Certbot finished. Killing http server..."

echo "Finiding certs. Exiting if certs are not found ..."
CERTPATH=/etc/letsencrypt/live/$(echo $DOMAINS | cut -f1 -d',')
ls $CERTPATH || exit 1

echo "Creating update for secret..."
cat /secret-patch-template.json | \
	sed "s/NAMESPACE/${NAMESPACE}/" | \
	sed "s/NAME/${SECRET}/" | \
	sed "s/TLSCERT/$(cat ${CERTPATH}/fullchain.pem | base64 | tr -d '\n')/" | \
	sed "s/TLSKEY/$(cat ${CERTPATH}/privkey.pem |  base64 | tr -d '\n')/" \
	> /secret-patch.json

echo "Checking json file exists. Exiting if not found..."
ls /secret-patch.json || exit 1

# Update Secret
echo "Updating secret..."
curl \
	--cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
	-H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
	-XPATCH \
	-H "Accept: application/json, */*" \
	-H "Content-Type: application/strategic-merge-patch+json" \
	-d @/secret-patch.json https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/${NAMESPACE}/secrets/${SECRET} \
	-k -v
echo "Done"
