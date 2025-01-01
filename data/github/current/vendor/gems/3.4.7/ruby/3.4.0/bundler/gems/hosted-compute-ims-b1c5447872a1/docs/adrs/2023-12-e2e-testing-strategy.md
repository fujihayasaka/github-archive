# IMS E2E Testing Strategy

## Status
Proposed

***

## Context
The purpose of this document is to outline possible testing strategies and tools we can use for our E2E tests.

Unlike Unit tests, the E2E tests will require us to validate the interactions between several dependencies. For IMS, those dependencies include Azure and Aqueduct 

![IMS Test Toolset](https://github.com/github/hosted-compute-ims/assets/32417800/af15d2c6-33b7-4a84-a566-9e452623ec85)
 _(image provided by @dev-tim)_


## Proposal

### Set up
- Environment variables 
  - We will need to set environment variables for tests under `script/test` or `Makefile` and access these variables using `go-config`
- Makefile
  -  Create a `test` target that: 
     -  Runs unit tests
   - Create a `e2e-test` target that:
     - Runs only e2e tests under the `internal/e2e` folder
     - Dump logs
- Changes to `script/test`
  - Creates the MySQL [container](https://github.com/github/hosted-compute-ims/blob/main/internal/store/mysql/testcontainer.go) and Aqueduct container with Go code that our tests can connect to ([example](https://github.com/cjfinnell/example-go-service-int-coverage/blob/7d2f4edacc139ee0682b2b9d853a10302425fc16/Makefile#L18))
- Testing resources
  - Each test run needs to create a resource group in the [VCFP_Eng](https://ms.portal.azure.com/#@microsoft.onmicrosoft.com/resource/subscriptions/16eb6e57-e88b-49c9-8acb-26048bee1f93/resourceGroups/lycb-runner/overview) subscription. Each resource group should have a unique identifier per test run. These resource groups should be cleaned up after the test run instances are finished. We decided to go with this subscription because it fits our use case for now (we already monitor and use it). In the future, we may pivot to a different solution. 
- Miscellaneous
  - Test file [should end with](https://go.dev/doc/tutorial/add-a-test#:~:text=The%20go%20test%20command%20executes,the%20tests%20and%20their%20results.) `_test.go` and live under the `internal/e2e` directory

### Running tests
- We should use the following test images with ~30 GB for size (images with this size take around 10-15 min to upload):
  - Our current Linux Debian image
  - Create a new Windows image
- All e2e tests should run in parallel to reduce the total duration
- Tests should timeout after 30 min of run time
  
#### Testing Scenarios
Our test scenarios should represent high fidelity interactions from dotcom for the purposes of managing images. 

_Customer images_
1) Customer X creates an image definition 1
2) Customer X creates versions 1.0.0 and 1.0.1 for existing image definition 1
4) Customer X wants a list of all versions [1.0.0, 1.0.1]
5) Customer X deletes version 1.0.0
6) Customer X creates another image definition 2
7) Customer X creates version 1.0.0 for existing image definition 2
8) Customer X wants a list of all image definitions [1, 2]
9) Customer X disables image definition 1
10) Customer X tries to list image versions in image definition 1 but got an error that image definition 1 was disabled
11) Customer X deletes image definition 1 and all its versions
12) Customer Y, an employee at another company, tries to access image definition 2 at Customer X's company and was met with the error that Customer Y does not have access to Customer X's images

_Curated images_
1) Customer Y gets a list of all curated image definitions supported by GitHub
2) Customer Y clicks on Ubuntu22 image definition and wants a list of all curated image versions

_Curated images (Admin)_
1) Admin X wants a list of all Curated images
2) Seeing that Ubuntu22 is not on the list, Admin X creates an image definition Ubuntu23 and created version 22.04.1 LTS for Ubuntu23
3) After creating Admin X realizes their mistake and renames Ubuntu23 to Ubuntu22
4) Admin X adds in another version 22.04.2 LTS for Ubuntu22
5) Now Admin X wants a list of all supported version in Ubuntu22 and Ubuntu20
6) Ubuntu20 has an unsupported version so Admin X deletes that version
7) Admin X also realizes that GitHub no longer supports Ubuntu16 so Admin X disables Ubuntu16 
8) After some time, Admin X disables version Ubuntu22.04.1 LTS because GitHub no longer supports it. 
9) Admin X creates an image definition Ubuntu24 and created versions 1.0.0, 1.0.1 for this image definition
10) Realizing that GitHub doesn't actually support Ubuntu24, Admin X tries to delete image definition Ubuntu24 altogether but fails because there are versions 
11) Admin X deletes versions 1.0.0 and 1.0.1 and deletes image definition again and it works
12) Customer Y (on their company's settings page) tries to get a list of all curated image definitions supported by GitHub. They see that Ubuntu22 is now supported by GitHub and Ubuntu16 is no longer supported

#### Assertions

For each endpoint, we can utilize the generated client to call the associated API methods. For now, we should use the Golang client. In the future, we can generate a Ruby client for Dotcom.

- `GET` & `LIST` endpoints
  - Interacts with Database only
  - Confirms that database returns back the correct row(s)
- `CREATE` endpoints
  - Image Version: interacts with Database, Aqueduct, and Azure
    - Confirms that new row is inserted into the `image_version` table in DB
    - Confirms that Aqueduct queued the job 
    - Confirms that Azure created a new image version + image definition
  - Image Definition: interacts with Database only
    - Confirms that new row is inserted into the `image_definition` table in DB
- `UPDATE` endpoints
  - Image Definition: interactions with Database only
    - Confirms that existing row was updated in the Database
- `DELETE` endpoints
  - Image Definition: interactions with Database only
    - Confirms that DB returns 0 rows for queried image definition after deleting
  - Image Version: interactions with Database, Aqueduct, and Azure
    - Confirms that `state` in image_version table is “Deleting”
    - Confirms that worker queued `DeleteImageVersionJob`
    - After the `DeleteImageVersionJob` runs, 
      - If image version == 0, confirm that the Azure Image Definition is deleted as well. 
      - If image version > 0, confirm that Azure did not delete the Azure Image Definition 

### Clean up
Tests should be implemented with a timeout function which narrowly exceeds the expected time taken. Any resources created during execution should be cleaned up immediately after either the timeout was exceeded or the tests completed (regardless of failure/success) If clean up fails, we should consider [implementing an automating job](https://github.com/github/c2c-actions/blob/main/docs/clean-azure-dev-bot.md) which deletes resources that haven't been used in X days. 
