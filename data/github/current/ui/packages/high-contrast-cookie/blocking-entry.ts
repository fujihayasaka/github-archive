/**
 * This file automatically registers this package with webpack and creates a blocking bundle named `high-contrast-cookie`
 * Any code written in high-contrast-cookie.js will run when the bundle is loaded.
 */

import {updateHtmlHighContrastMode} from './high-contrast-cookie'

updateHtmlHighContrastMode()
