import type {ICookieCategoriesPreferences} from 'consent-banner'

export const CookieCategoryId = {
  Required: 'Required',
  Analytics: 'Analytics',
  SocialMedia: 'SocialMedia',
  Advertising: 'Advertising',
} as const

export const privacyPolicyUrl = 'https://docs.github.com/site-policy/privacy-policies/github-privacy-statement'
export const cookieInventoryUrl =
  'https://docs.github.com/site-policy/privacy-policies/github-subprocessors-and-cookies'
export const docsURL =
  'https://docs.github.com/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-personal-account-settings/managing-your-cookie-preferences-for-githubs-enterprise-marketing-pages'

const consentRequiredPreferences: ICookieCategoriesPreferences = {
  [CookieCategoryId.Required]: true,
  [CookieCategoryId.Analytics]: false,
  [CookieCategoryId.SocialMedia]: false,
  [CookieCategoryId.Advertising]: false,
}

const consentNotRequiredPreferences: ICookieCategoriesPreferences = {
  [CookieCategoryId.Required]: true,
  [CookieCategoryId.Analytics]: true,
  [CookieCategoryId.SocialMedia]: true,
  [CookieCategoryId.Advertising]: true,
}

export const DefaultCookieConsentPreferences = {
  Required: consentRequiredPreferences,
  NotRequired: consentNotRequiredPreferences,
}

export const themes = {
  /**
   * Use the same defaults that the built-in dark theme uses:
   * https://github.com/microsoft/consent-banner/blob/f38eff3a2f26d2724941db5ef1815e1c58fd134d/src/themes/theme-styles.ts#L41
   * */
  github: {
    /* Required theme properties */
    'close-button-color': '#d8b9ff',
    'secondary-button-disabled-opacity': '0.5',
    'secondary-button-hover-shadow': 'none',
    'primary-button-disabled-opacity': '0.5',
    'primary-button-hover-border': '1px solid transparent',
    'primary-button-disabled-border': '1px solid transparent',
    'primary-button-hover-shadow': 'none',
    'banner-background-color': '#24292f',
    'dialog-background-color': '#24292f',
    'primary-button-color': '#ffffff',
    'text-color': '#ffffff',
    'secondary-button-color': '#32383f',
    'secondary-button-disabled-color': '#424a53',
    'secondary-button-border': '1px solid #eaeef2',

    /* Optional theme properties */
    'background-color-between-page-and-dialog': 'rgba(23, 23, 23, 0.8)',
    'dialog-border-color': '#d8b9ff',
    'hyperlink-font-color': '#d8b9ff',
    'secondary-button-hover-color': '#24292f',
    'secondary-button-hover-border': '1px solid #ffffff',
    'secondary-button-disabled-border': '1px solid #6e7781',
    'secondary-button-focus-border-color': '#6e7781',
    'secondary-button-text-color': '#ffffff',
    'secondary-button-disabled-text-color': '#ffffff',
    'primary-button-hover-color': '#d8b9ff',
    'primary-button-disabled-color': '#ffffff',
    'primary-button-border': '1px solid #ffffff',
    'primary-button-focus-border-color': '#ffffff',
    'primary-button-text-color': '#1f2328',
    'primary-button-disabled-text-color': '#1f2328',
    'radio-button-border-color': '#d8b9ff',
    'radio-button-checked-background-color': '#d8b9ff',
    'radio-button-hover-border-color': '#ffffff',
    'radio-button-hover-background-color': '#ffffff',
    'radio-button-disabled-color': 'rgba(227, 227, 227, 0.2)',
    'radio-button-disabled-border-color': 'rgba(227, 227, 227, 0.2)',
  },
}
