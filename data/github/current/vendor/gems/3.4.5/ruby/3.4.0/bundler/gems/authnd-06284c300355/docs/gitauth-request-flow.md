# GitAuth Request Flows

## Overview

Git operations at GitHub are served by [babeld](https://github.com/github/babeld) which listens at the HTTPS/SSH endpoints Git expects.
It performs SSH handshaking, etc. and then makes internal HTTP request calls to [gitauth](https://github.com/github/github/blob/master/gitauth.ru) to process authentication data.
This doc outlines the basic request/response flows between babeld and gitauth. 

NOTE: In the requests/responses below, newlines have been added to request/response bodies for readability.
Lines starting `>` indicate requests sent from babeld to gitauth.
Lines starting `<` indicate the response from gituath to babeld.

## 1a. SSH Key resolution

*SSH Only*

**NOTE**: Babeld *does* cache this result so that subsequent connections from the same key may not generate this request and may move directly to the auth request.

For SSH operations, the first request babeld makes to gitauth is to resolve the SSH key into a user ID and user name:

```
> POST /_gitauth HTTP/1.1
> Host: 127.0.0.1:4327
> Accept: */*
> User-Agent: babeld/bcaadb19
> X-GLB-Via: hostname=aerith.lan t=1594406151491.248
> X-GitHub-Request-Id: 99d0b2e2ad45aac1ddab08f601ca1142
> Content-Length: 880
> Content-Type: application/x-www-form-urlencoded
>
> action=verify-key&
> proto=ssh&
> fingerprint=0d:15:55:ad:98:65:5c:8d:c5:35:dc:5a:8b:7f:25:05&
> key=ssh-rsa%20<snipped for brevity>&
> ssh_login=git
```

The response is either a `403` indicating the SSH key is unknown, or a `200` with user information: 

```
< HTTP/1.1 200 OK
< Date: Fri, 10 Jul 2020 18:35:51 GMT
< Status: 200 OK
< Connection: close
< Content-Length: 15
< Content-Type: text/plain
< X-GitHub-Request-Id: 99d0b2e2ad45aac1ddab08f601ca1142
<
< user:2:monalisa
```

## 1b. Anonymous check

*HTTP(S) Only*

For HTTP(S) operations, babeld first attempts an anonymous access check to see if authentication is required:

```
> POST /_gitauth HTTP/1.1
> Host: 127.0.0.1:4327
> Accept: */*
> User-Agent: babeld/bcaadb19
> X-GLB-Via: hostname=aerith.lan t=1594408160046.839
> X-GitHub-Request-Id: 5621c98a8a35fd22e03447e16679de02
> X-Original-User-Agent: git/2.24.3 (Apple Git-128)
> Content-Length: 85
> Content-Type: application/x-www-form-urlencoded
>
> path=monalisa%2Ftest-repo.git&
> action=read&
> proto=http&
> srcip=&
> hostname=github.localhost
```

The response is either a `403` indicating anonymous access is not permitted, or a `200` with repo DFS routing information:

```
< HTTP/1.1 200 OK
< Date: Fri, 10 Jul 2020 19:09:20 GMT
< Status: 200 OK
< Connection: close
< Content-Length: 1082
< Content-Type: text/plain
< X-GitHub-Request-Id: 2de93def5358770e827fefca755b4afd
<
< { ... snipped JSON related to DFS routing ... }
```

## 2. Authorized user check

This step is used in SSH connections, or HTTP(S) connections where anonymous access is not permitted.
This request from babeld includes credentials.
For SSH connections this is the first request to include repository and permission information.

Of note here is that since a username is expected, babeld has to make the `verify-key` call (1a above) for SSH connections in order to resolve a user ID and username.

For SSH connections, the request contains the key, and username:

```
> POST /_gitauth HTTP/1.1
> Host: 127.0.0.1:4327
> Accept: */*
> User-Agent: babeld/bcaadb19
> X-GLB-Via: hostname=aerith.lan t=1594406151694.686
> X-GitHub-Request-Id: 99d0b2e2ad45aac1ddab08f601ca1142
> Content-Length: 939
> Content-Type: application/x-www-form-urlencoded
>
> path=monalisa%2Ftest-repo.git&
> member=user%3A2%3Amonalisa&
> action=write&
> proto=ssh&
> fingerprint=0d:15:55:ad:98:65:5c:8d:c5:35:dc:5a:8b:7f:25:05&
> key=ssh-rsa%20<snipped>&
> srcip=&
> ssh_login=git
```

For HTTP(S) connections, the request contains the username and password **OR** token.
Since HTTP(S) connections use Basic auth to pass tokens, there is no way to distinguish passwords, OAuth tokens or Personal Access Tokens.
Even though a username is provided when authenticating with a token, it is disregarded.

```
> POST /_gitauth HTTP/1.1
> Host: 127.0.0.1:4327
> Accept: */*
> User-Agent: babeld/bcaadb19
> X-GLB-Via: hostname=aerith.lan t=1594406872901.807
> X-GitHub-Request-Id: 46feb5d60d7a12ab3140f947ce056a0e
> X-Original-User-Agent: git/2.24.3 (Apple Git-128)
> Content-Length: 121
> Content-Type: application/x-www-form-urlencoded
>
> member=monalisa&
> password=passworD1&
> path=monalisa%2Ftest-repo.git&
> action=write&
> proto=http&
> srcip=&
> hostname=github.localhost
```

Gitauth responds with either a `403` if access is denied or a `200`, with DFS routing information, if access is allowed

```
< HTTP/1.1 200 OK
< Date: Fri, 10 Jul 2020 19:09:20 GMT
< Status: 200 OK
< Connection: close
< Content-Length: 1082
< Content-Type: text/plain
< X-GitHub-Request-Id: 99d0b2e2ad45aac1ddab08f601ca1142
<
< { ... snipped JSON related to DFS routing ... }
```

## 3. Commit Refs

This is mostly out-of-scope for Wall-E.
After babeld finishes pushing information to the DFS, it pings back to gitauth to actually update the branch.
There is some authz here in that babeld sends a user ID and gitauth checks for branch protection rules:

```
> POST /_commit_refs HTTP/1.1
> Host: 127.0.0.1:4327
> Accept: */*
> User-Agent: babeld/bcaadb19
> X-GLB-Via: hostname=aerith.lan t=1594406154741.508
> X-GitHub-Request-Id: 99d0b2e2ad45aac1ddab08f601ca1142
> Content-Length: 1700
> Content-Type: application/x-www-form-urlencoded
> 
> {
>     "repo_name":"monalisa/test-repo",
>     "commit_ref_ctx":"{\"user_id\":2,\"auth_type\":\"user\"}",
>     ... other non-auth info ...
> }
```

Gitauth responds with a `200` in both success and error cases, with details in the JSON payload.
For requests blocked by branch protection:

```
< HTTP/1.1 200 OK
< Date: Fri, 10 Jul 2020 18:35:55 GMT
< Status: 200 OK
< Connection: close
< Content-Type: application/json
< X-GitHub-Request-Id: 99d0b2e2ad45aac1ddab08f601ca1142
< Transfer-Encoding: chunked
<
< eb
< {"ok":true,"err":"error: GH006: Protected branch update failed for refs/heads/master.\nerror: At least 1 approving review is required by reviewers with write access.\n","refs":{"refs%2Fheads%2Fmaster":"protected branch hook declined"}}
< 0
```

Or for a successful request:

```
< HTTP/1.1 200 OK
< Date: Fri, 10 Jul 2020 18:47:56 GMT
< Status: 200 OK
< Connection: close
< Content-Type: application/json
< X-GitHub-Request-Id: 30a20c16140635c40015ebe73b71d025
< Transfer-Encoding: chunked
<
< 8c
< {"ok":true,"err":"","refs":{"refs%2Fheads%2Fmaster":"ok f1d9436861b04e2d8e0863d54929121365691627 6838e7148e68e29f0c1cdeb685234673b83332aa"}}
< 0
```
