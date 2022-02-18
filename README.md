# letsngrok

Inspired by:
https://hub.docker.com/r/sjenning/kube-nginx-letsencrypt/


```shell
op get document secret.ngrok-token.yaml --vault automation | kubectl apply -f -
```

nerdctl run -ti --env NGROK_AUTHTOKEN=T0KeN ngrok/ngrok http 80 --region=us --hostname=ngrok.fervid.us