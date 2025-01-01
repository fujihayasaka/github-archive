/*
 *  These packages and their dependencies are published to our private NPM registry. They are exempt from
 * the "private: true" lint check and are required to have a "version: x.x.x".
 */

// Commented out packages have not been published yet, but will be eventually
// If PUBLISHED_PACKAGES is updated, restart your eslint local server to compile a new list of published packages
const PUBLISHED_PACKAGES = [
  //---- start of published packages ----
  'filter',
  'github-avatar',
  'list-view',
  // 'action-bar',
  // 'action-list-items',
  'date-picker',
  // 'drag-and-drop',
  // 'inline-autocomplete',
  // 'list-view',
  // 'nested-list-view',
  // 'simple-list-view',
  //---- end of published files ----
]

module.exports = PUBLISHED_PACKAGES
