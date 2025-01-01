# Testing the Twirp Endpoint

## Prerequisites

1. Connect to the [GitHub IAD Production VPN](https://thehub.github.com/security/security-operations/production-vpn-access/).

## Steps to Test

1. **Build the Client Command**

   Run the following command to build the client:
   ```sh
   make build
   ```

2. **Test the Reverse Endpoint**

   Use the following command to hit the reverse endpoint:
   ```sh
   ./bin/twirp-test reverse me --url https://attester-production.service.iad.github.net
   ```

   **Output:**
   ```sh
   Calling Twirp server at https://attester-production.service.iad.github.net with name me...
   Received response from server: em
   ```

3. **Test the Hello Endpoint**

   Use the following command to hit the hello endpoint:
   ```sh
   ./bin/twirp-test hello me --url https://attester-production.service.iad.github.net
   ```

   **Output:**
   ```sh
   Calling Twirp server at https://attester-production.service.iad.github.net with name me...
   Received response from server: me
   ```
