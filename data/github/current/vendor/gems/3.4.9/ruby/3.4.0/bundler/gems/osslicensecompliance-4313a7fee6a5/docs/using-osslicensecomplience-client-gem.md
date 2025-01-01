# Working with osslicensecompliance in the monolith

*Table of Contents*
- [Working with osslicensecompliance in the monolith](#working-with-osslicensecompliance-in-the-monolith)
  - [Calling osslicensecompliance twirp endpoints from the monolith](#calling-osslicensecompliance-twirp-endpoints-from-the-monolith)
  - [Setup new/edited osslicensecompliance twirp endpoint in the monolith](#setup-newedited-osslicensecompliance-twirp-endpoint-in-the-monolith)
  - [Update osslicensecompliance-client gem in the monolith](#update-osslicensecompliance-client-gem-in-the-monolith)

## Calling osslicensecompliance twirp endpoints from the monolith

- the wrappers for calling osslicensecompliance twirp endpoints are defined in [lib/oss_license_compliance/twirp/oss_license_compliance_client.rb](https://github.com/github/github/blob/master/lib/oss_license_compliance/twirp/oss_license_compliance_client.rb)
  - if the endpoint isn’t in this file, see [Setup new/edited osslicensecompliance twirp endpoint in the monolith](#setup-newedited-osslicensecompliance-twirp-endpoint-in-the-monolith)
- examples of calling endpoint wrappers are at [test/lib/oss_license_compliance/twirp/](https://github.com/github/github/blob/f742b5381482d87fed2d2aa6673db88bc5e7dd6c/test/lib/oss_license_compliance/twirp/oss_license_compliance_client_test.rb#L74-L131)

## Setup new/edited osslicensecompliance twirp endpoint in the monolith

- update the gem in the monolith if needed, see [Update osslicensecompliance gem in the monolith](#update-osslicensecompliance-gem-in-the-monolith)
- add wrapper for the new endpoint in [lib/oss_license_compliance/twirp/oss_license_compliance_client.rb](https://github.com/github/github/blob/master/lib/oss_license_compliance/twirp/oss_license_compliance_client.rb)
  - add sig definition for endpoint wrapper based on generated sorbet files
    - params match the sorbet generated sig params for the Request (e.g. [sorbet/rbi/dsl/oss_license_compliance/v0/create_enterprise_policy_request.rbi](https://github.com/github/github/blob/938d7f800d5472712ca29811ed304b80bc456e83/sorbet/rbi/dsl/oss_license_compliance/v0/create_enterprise_policy_request.rbi#L9-L16)*)
    - returns matches the sorbet generated Response class (e.g. `OSSLicenseCompliance::V0::CheckRepositoryResponse` defined in [sorbet/rbi/dsl/oss_license_compliance/v0/check_repository_response.rbi](https://github.com/github/github/blob/master/sorbet/rbi/dsl/oss_license_compliance/v0/check_repository_response.rbi))
  - write the body of method
    - setup Request object using passed in parameters
    - send the rpc call with the request (*This returns the response from the endpoint*)
- write a test in [test/lib/oss_license_compliance/twirp/](https://github.com/github/github/tree/master/test/lib/oss_license_compliance/twirp)
  - name the file for the endpoint wrapper you added (e.g. create_enterprise_policy_test.rb)
  - use one of the existing test files for another twirp call as an example for the contents of the test file

## Update osslicensecompliance-client gem in the monolith

- open [github/github](https://github.com/github/github) codespace
- may need to run `script/bootstrap` if it doesn’t autostart (*wait for it to complete*)
  - check to see if bootstrap is running using `ps`, where the output being anything other than the grep command means it is still running
```
$ ps -aux | grep bootstrap | grep -v 'out/bootstrap' | grep -v 'bootstrap.Elasticsearch'
vscode     28380  0.0  0.0   8200  2304 pts/3    S+   11:25   0:00 grep --color=auto bootstrap
```
- update sha in [Gemfile](https://github.com/github/github/blob/master/Gemfile) for `osslicensecompliance-client`
- run: `bundle install`
- confirm that [Gemfile.lock](https://github.com/github/github/blob/master/Gemfile.lock) has the new sha
- generate RBI files
  - run: `bin/tapioca gem osslicensecompliance-client` (*required*)
    - generated into: [sorbet/rbi/gems/](https://github.com/github/github/tree/master/sorbet/rbi/gems)`osslicensecompliance-client@<version><short-sha><full-sha>` (*make sure sha matches that of the new gem*)
  - run: `bin/tapioca dsl` (*only needed if there are new or changes to twirp endpoints or structures/enums in types*)
    - generates `_request` and `_response` files into: [sorbet/rbi/dsl/oss_license_compliance](https://github.com/github/github/tree/master/sorbet/rbi/dsl/oss_license_compliance)/v0/ (*version v0 will change as there are new major releases of osslicensecompliance*)
    - if new endpoints, check that new endpoints were added (*see additional steps in [Setup new/edited osslicensecompliance twirp endpoint in the monolith](#setup-newedited-osslicensecompliance-twirp-endpoint-in-the-monolith) in the monolith*)
    - if changes to existing endpoints that will impact generated files (e.g. changes to major version, rpc message name, request/response name or structure), check that new files are generated for the `Request` class (e.g. check_repository_request.rbi) and `Response` class (e.g. check_repository_response.rbi)

