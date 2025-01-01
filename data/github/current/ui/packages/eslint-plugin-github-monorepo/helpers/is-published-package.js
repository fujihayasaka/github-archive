const {basename} = require('path')
const PUBLISHED_PACKAGES = require('../published-packages')

// @ts-check
/**
 * @param {string} path
 * @returns {boolean}
 */
const isPublishedPackage = path => PUBLISHED_PACKAGES.includes(basename(path))

module.exports = isPublishedPackage
