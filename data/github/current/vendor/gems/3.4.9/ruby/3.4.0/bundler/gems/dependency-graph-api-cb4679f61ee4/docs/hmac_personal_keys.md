# Temporary HMAC token with GraphiQL
Sometimes you just need a temporary HMAC token to do some testing, eg with [GraphiQL](https://github.com/skevy/graphiql-app). Luckily we allow 10 minutes of clock drift with our HMAC tokens, so you can generate a token that will be valid for 10 minutes. Perfect for quick tests against the production API!

Here's how to do it
1) Visit [#dg-ops](https://slack.com/app_redirect?channel=dg-ops) in Slack
2) Run the `.dg hmac` ChatOp
3) In GraphiQl go to "Edit HTTP Headers" and set `X-Request-Hmac` to the token you got in step 2.

# Permanent HMAC personal keys

We need to use HMAC in order to secure communication to the dependency graph because it stores private repository information. Relying on the security of the VPN is not enough!

Unfortunately, the above makes it a bit harder to query production. Here's how to do it anyway:

1) Get [on the VPN](https://githubber.com/article/crafts/engineering/production-vpn-access).
2) Get someone from [#dependency-graph](https://slack.com/app_redirect?channel=dependency-graph) with vault access to set up an HMAC key for you (if that person is you, read on!)
3) Make sure the key works with curl

``` bash
$ export HMAC_KEY=<THE KEY>
$ curl -XPOST -v -H "Content-Type: application/json" \
  -H "X-Request-Hmac: `printf "%s.%s" $(date +%s) $(date +%s | tr -d '\n' | openssl dgst -sha256 -hmac $HMAC_KEY)`" \
  --data '{"query": "{manifests(repositoryIds:[69299342]){edges{node{id}}}}"}' \
  https://dependency-graph-api.service.iad.github.net/query
```

## Adding personal keys

First of all, make sure you have [access to vault](https://githubber.com/article/crafts/engineering/internal/configuration-variables-for-applications#viewing-and-setting-configuration-with-vault)

Once you're logged in to vault, you're going to be adding a key to the `DEPENDENCY_GRAPH_API_HMAC_KEYS` variable. Note that it contains several keys separated by spaces. It's important that the main production key come first and all the other keys come after it.

1) Generate a key for the new user. We prefix the keys with the username or intended use, e.g. a key for @mveytsman would be something like `mveytsman_deadbeef123123` (not a real key!). You can generate it like this: 

``` bash
$ KEY_NAME=<THE USERNAME THE KEY IS FOR>
$ KEY=$(ruby -e "name = '$KEY_NAME'; require 'securerandom'; puts name + '_' + SecureRandom.hex(32)") 
```

2) Add the key:

``` bash
$ CURRENT_KEYS=$(vault-secret --application dependency-graph-api --key DEPENDENCY_GRAPH_API_HMAC_KEYS)
$ NEW_KEYS="$CURRENT_KEYS $KEY"
$ echo $NEW_KEYS # Make sure this is correct!
$ vault-secret --application dependency-graph-api --key DEPENDENCY_GRAPH_API_HMAC_KEYS --value="$NEW_KEYS" # This sets the key value, don't forget the "'s around $NEW_KEYS!
$ vault-secret --application dependency-graph-api --key DEPENDENCY_GRAPH_API_HMAC_KEYS # Double check to make sure the value is correct
```
3) Re-deploy dependency graph in order to pick up the new key environment variable

## SSH proxy + Postman client

### Requirements:

1. Ensure you have [Production Shell Access](https://githubber.com/article/technology/production-shell-access)
1. Generate a temporary HMAC or your own HMAC personal key (see [HMAC](#temporary-hmac-token-with-graphiql))
1. [Postman Client](https://www.postman.com/downloads/) installed

### Steps

Connect to bastion server via SSH and enable port forwarding:
``` bash
ssh -N -L 5555:dependency-graph-api.service.iad.github.net:443 bastion.githubapp.com
``` 
Open Postman or any other client:
1. Disable HTTPS validation. In Postman it should be under (Settings -> General -> SSL Certificate verification) 
Note: please re-enable this once you are done testing
1. Edit Headers:
   1. Add `X-Request-Hmac` key and enter your [HMAC]((#temporary-hmac-token-with-graphiql))
   1. Add `Host` and enter `dependency-graph-api.service.iad.github.net`

1. Submit POST to https://localhost:5555/query (Or whatever ports you used)
``` graphql
query {
manifests(repositoryIds:[69299342]){ edges { node { id } } }
}
```
Note: Sometimes the port you used remains in listening mode. Run the following to kill it:
 ```bash
 lsof -n -i4TCP:5555 -sTCP:LISTEN -t | xargs kill
```
## Revocation

Hopefully you won't have to do this, but if you do it's pretty straightforward. Just get the list of keys with

``` bash
$ vault-secret --application dependency-graph-api --key DEPENDENCY_GRAPH_API_HMAC_KEYS
```

You can take that string and edit it to delete the key you want to revoke. Then run 

``` bash
vault-secret --application dependency-graph-api --key DEPENDENCY_GRAPH_API_HMAC_KEYS --prompt
```

and paste the new value in when prompted. As always, triple check to make sure you're setting the secret to the right value.

Don't forget to redeploy for the changes to take effect!

## Sample client code

### Bash/Curl

``` bash
$ export HMAC_KEY=<THE KEY>
$ curl -XPOST -v -H "Content-Type: application/json" \
  -H "X-Request-Hmac: `printf "%s.%s" $(date +%s) $(date +%s | tr -d '\n' | openssl dgst -sha256 -hmac $HMAC_KEY)`" \
  --data '{"query": "{manifests(repositoryIds:[69299342]){edges{node{id}}}}"}' \
  https://dependency-graph-api.service.iad.github.net/query
```

### Ruby

``` ruby
require 'faraday'
key = <THE KEY>
timestamp = Time.now.to_i.to_s
digest =  OpenSSL::Digest::SHA256.new
hmac = OpenSSL::HMAC.new(key, digest)
hmac << timestamp

response = Faraday.post "https://dependency-graph-api.service.iad.github.net/query" do |req|
  req.headers['Content-Type'] = 'application/json'
  req.headers['X-Request-Hmac'] = "#{timestamp}.#{hmac}"
  req.body = '{"query": "{manifests(repositoryIds:[69299342]){edges{node{id}}}}"}'
end

puts response.body
```

### Python

``` python
import hmac
import requests
import hashlib

key = <THE KEY>
ts = str(int(time.time()))
key = bytes(key, 'utf-8')
message = bytes(ts, 'utf-8')

digester = hmac.new(key, message, hashlib.sha256)
signature1 = digester.hexdigest()

r = requests.post('https://dependency-graph-api.service.iad.github.net/query',
                  headers={'X-Request-Hmac': ts + "." + signature1},
                  data="YOUR QUERY HERE")
r.text
```
