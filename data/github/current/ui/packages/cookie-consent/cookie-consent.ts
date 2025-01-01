import {setCookie, getCookie} from '@github-ui/cookies'
import type {ICookieCategoriesPreferences, ConsentControl} from 'consent-banner'
// Remove this line and replace `withResolvers` with `Promise.withResolvers`
// the day we know no polyfilling is necessary.
import {withResolvers} from '@github-ui/promise-with-resolvers-polyfill'

import {cookieCategories, consentControlOptions, DefaultCookieConsentPreferences} from './lib/configuration'

type CookieConsentPreferencesType = {
  [key: string]: boolean | undefined
}

export const CONSENT_COOKIE_NAME = 'GHCC'

const SIX_MONTHS = 1000 * 60 * 60 * 24 * 180 // 180 days in milliseconds
const CONSENT_COOKIE_EXPIRATION_DATE = new Date(Date.now() + SIX_MONTHS) // 6 months from now

let consentControlInstance: ConsentControl | undefined

const onPreferenceChange = async (preferences: ICookieCategoriesPreferences) => {
  setPreferencesToCookie(preferences)
  consentControlInstance?.hideBanner()
}

export async function initializeConsentControl() {
  const {ConsentControl} = await import('consent-banner')

  consentControlInstance = new ConsentControl('ghcc', 'en', onPreferenceChange, cookieCategories, consentControlOptions)

  return consentControlInstance
}

export function showPreferences() {
  consentControlInstance?.showPreferences(getPreferencesFromCookie() || {})
}

export function showCookieBanner() {
  consentControlInstance?.showBanner(DefaultCookieConsentPreferences.Required)
}

export function setConsentToAcceptAll() {
  setPreferencesToCookie(DefaultCookieConsentPreferences.NotRequired)
}

export function hasNoCookiePreferences() {
  return getPreferencesFromCookie() === null
}

const consentPromiseWithResolvers = withResolvers<CookieConsentPreferencesType>()

export function waitForConsentPreferences(): Promise<CookieConsentPreferencesType> {
  return consentPromiseWithResolvers.promise
}

function setPreferencesToCookie(preferences: CookieConsentPreferencesType): void {
  const consentPreferences = Object.keys(preferences)
    .map(cookieCategoryId => `${cookieCategoryId}:${preferences[cookieCategoryId] ? '1' : '0'}`)
    .join('-')

  setCookie(CONSENT_COOKIE_NAME, consentPreferences, CONSENT_COOKIE_EXPIRATION_DATE.toUTCString())
  consentPromiseWithResolvers.resolve(preferences)
}

export function getPreferencesFromCookie(): CookieConsentPreferencesType | null {
  const preferencesCookie = getCookie(CONSENT_COOKIE_NAME)

  if (!preferencesCookie) {
    return null
  }

  const preferences = preferencesCookie.value.split('-')
  const cookieCategoriesPreferences: CookieConsentPreferencesType = {}

  for (const cookieParts of preferences) {
    const [cookieCategoryId, preference] = cookieParts.split(':')

    if (cookieCategoryId) {
      cookieCategoriesPreferences[cookieCategoryId] = preference === '1'
    }
  }

  return cookieCategoriesPreferences
}

const initialConsent = getPreferencesFromCookie()

if (initialConsent) {
  consentPromiseWithResolvers.resolve(initialConsent)
}
