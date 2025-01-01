// eslint-disable-next-line import/no-namespace
import * as English from './configuration.en'
// eslint-disable-next-line import/no-namespace
import * as Portuguese from './configuration.pt'
// eslint-disable-next-line import/no-namespace
import * as Japanese from './configuration.ja'
// eslint-disable-next-line import/no-namespace
import * as Spanish from './configuration.es'
// eslint-disable-next-line import/no-namespace
import * as Korean from './configuration.ko'

export interface LanguageConfig {
  cookieCategories: typeof English.cookieCategories
  consentControlOptions: typeof English.consentControlOptions
}

export const languageConfigs: {[locale: string]: LanguageConfig} = {
  en: English,
  pt: Portuguese,
  ja: Japanese,
  es: Spanish,
  ko: Korean,
  // Add more languages here as needed
}
