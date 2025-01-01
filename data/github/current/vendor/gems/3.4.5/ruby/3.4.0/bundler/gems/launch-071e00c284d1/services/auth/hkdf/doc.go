// Package hkdf generates keys for HMAC-ing action-runner messages
//
// # Crypto Scheme for action-runner
//
// - we share a secret between deployer and receiver
// - deployer generates a signing key for each build and passes it to action-runner
// .  - we reduce impact of keys being leaked as they're build-scoped and time-limited
//   - the risk we're mitigating is from container break-outs: action-runner is a sibling container of action executions
//
// - action-runner signs its messages to launch-receiver with the key, which launch-receiver uses to validate the messages' authenticity
package hkdf
