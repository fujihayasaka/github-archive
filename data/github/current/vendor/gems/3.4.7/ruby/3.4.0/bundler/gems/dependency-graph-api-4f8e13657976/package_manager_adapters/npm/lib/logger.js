// Public: Output a log message that's structured for Splunk.
module.exports = function log(message) {
  console.log(`now="${new Date().toISOString()}" package_manager=npm log_message="${message}"`)
}
