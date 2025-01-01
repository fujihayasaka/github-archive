import type {SearchResults} from '../types'
import {getValidCaseInsensitiveOption, getValidFilterValueFromParsedQuery} from './filters'

export const allTasksOptionID = 'all'
export const taskOptions = [
  {id: allTasksOptionID, name: 'All'},
  {id: 'chat-completion', name: 'Chat/completion'},
  {id: 'embeddings', name: 'Embeddings'},
]
export function selectedTaskName(rawTask: string | undefined | null) {
  const normalizedTask = rawTask?.toLowerCase() ?? allTasksOptionID
  const selectedOption = taskOptions.find(option => option.id === normalizedTask)
  return selectedOption?.name ?? rawTask
}
export const inputModalityOptions = ['audio', 'image', 'text']
export const outputModalityOptions = ['embeddings', 'text']
export const licenseOptions = [
  {id: 'custom', name: 'Custom'},
  {id: 'mit', name: 'MIT'},
]
export const allPublishersOption = 'All'
export const publisherOptions = [
  allPublishersOption,
  'AI21 Labs',
  'Cohere',
  'Core42',
  'DeepSeek',
  'Meta',
  'Mistral AI',
  'Microsoft',
  'OpenAI',
]
export const allCategoriesOptionID = 'All'
export const categoryOptions = [
  {id: allCategoriesOptionID, name: 'All'},
  {id: 'agents', name: 'Agents'},
  {id: 'conversation', name: 'Conversation'},
  {id: 'large context', name: 'Large context'},
  {id: 'low latency', name: 'Low latency'},
  {id: 'multilingual', name: 'Multilingual'},
  {id: 'multimodal', name: 'Multimodal'},
  {id: 'multipurpose', name: 'Multipurpose'},
  {id: 'rag', name: 'RAG'},
  {id: 'reasoning', name: 'Reasoning'},
  {id: 'understanding', name: 'Understanding'},
]
export const languageOptions = [
  {id: 'af', name: 'Afrikaans'},
  {id: 'ar', name: 'Arabic'},
  {id: 'bn', name: 'Bengali'},
  {id: 'zh', name: 'Chinese'},
  {id: 'zh-cn', name: 'Chinese (Simplified)'},
  {id: 'cs', name: 'Czech'},
  {id: 'da', name: 'Danish'},
  {id: 'nl', name: 'Dutch'},
  {id: 'en', name: 'English'},
  {id: 'eo', name: 'Esperanto'},
  {id: 'et', name: 'Estonian'},
  {id: 'fi', name: 'Finnish'},
  {id: 'fr', name: 'French'},
  {id: 'de', name: 'German'},
  {id: 'el', name: 'Greek'},
  {id: 'gu', name: 'Gujarati'},
  {id: 'ha', name: 'Hausa'},
  {id: 'he', name: 'Hebrew'},
  {id: 'hi', name: 'Hindi'},
  {id: 'hu', name: 'Hungarian'},
  {id: 'is', name: 'Icelandic'},
  {id: 'id', name: 'Indonesian'},
  {id: 'it', name: 'Italian'},
  {id: 'ja', name: 'Japanese'},
  {id: 'jv', name: 'Javanese'},
  {id: 'kn', name: 'Kannada'},
  {id: 'ko', name: 'Korean'},
  {id: 'lv', name: 'Latvian'},
  {id: 'ml', name: 'Malayalam'},
  {id: 'mr', name: 'Marathi'},
  {id: 'ne', name: 'Nepali'},
  {id: 'no', name: 'Norwegian'},
  {id: 'or', name: 'Odia'},
  {id: 'ps', name: 'Pashto'},
  {id: 'fa', name: 'Persian'},
  {id: 'pl', name: 'Polish'},
  {id: 'pt-br', name: 'Portuguese (Brazil)'},
  {id: 'pt', name: 'Portuguese'},
  {id: 'pa', name: 'Punjabi'},
  {id: 'ro', name: 'Romanian'},
  {id: 'ru', name: 'Russian'},
  {id: 'es', name: 'Spanish'},
  {id: 'sw', name: 'Swahili'},
  {id: 'sv', name: 'Swedish'},
  {id: 'tl', name: 'Tagalog'},
  {id: 'ta', name: 'Tamil'},
  {id: 'te', name: 'Telugu'},
  {id: 'th', name: 'Thai'},
  {id: 'tr', name: 'Turkish'},
  {id: 'uk', name: 'Ukrainian'},
  {id: 'ur', name: 'Urdu'},
  {id: 'vi', name: 'Vietnamese'},
  {id: 'cy', name: 'Welsh'},
  {id: 'yo', name: 'Yoruba'},
]
export const sortOptions: Record<string, string> = {
  'name-asc': 'Alphabetical',
  'created-desc': 'Recently added',
  'output-tokens-desc': 'Output token limit',
  'input-tokens-desc': 'Input token limit',
  popularity: 'Popularity',
}

// Keep in sync with `DEFAULT_MODELS_SORT_VALUE` in app/helpers/marketplace_helper.rb
export const defaultSortValue = 'created-desc'

export function getDefaultSort(sortValue: string | undefined, parsedQuery: SearchResults['parsedQuery']) {
  const validOptions = Object.keys(sortOptions)
  const sortFromParsedQuery = getValidFilterValueFromParsedQuery('sort', parsedQuery, validOptions)
  if (sortFromParsedQuery) return sortFromParsedQuery
  return getValidCaseInsensitiveOption(sortValue, validOptions) || defaultSortValue
}

export function getDefaultCategory(searchParams: URLSearchParams, parsedQuery: SearchResults['parsedQuery']) {
  const validOptions = categoryOptions.map(option => option.id)
  if (validOptions.includes(searchParams.get('category') || '')) {
    return searchParams.get('category')
  }
  const categoryFromParsedQuery = getValidFilterValueFromParsedQuery('category', parsedQuery, validOptions)
  if (categoryFromParsedQuery) return categoryFromParsedQuery
  return null
}

export function getDefaultTask(searchParams: URLSearchParams, parsedQuery: SearchResults['parsedQuery']) {
  const taskFromParams = searchParams.get('task') || ''
  const validOptions = taskOptions.map(({id}) => id)
  if (validOptions.includes(taskFromParams.toLowerCase())) return taskFromParams

  const taskFromParsedQuery = getValidFilterValueFromParsedQuery('task', parsedQuery, validOptions)
  return taskFromParsedQuery ?? allTasksOptionID
}

export function getDefaultPublisher(searchParams: URLSearchParams, parsedQuery: SearchResults['parsedQuery']) {
  const publisherFromParams = searchParams.get('publisher') || ''
  if (publisherOptions.includes(publisherFromParams)) return publisherFromParams

  const publisherFromParsedQuery = getValidFilterValueFromParsedQuery('publisher', parsedQuery, publisherOptions)
  return publisherFromParsedQuery ?? allPublishersOption
}

export function getValidCategoryFromParsedQuery(parsedQuery: SearchResults['parsedQuery']) {
  return getValidFilterValueFromParsedQuery(
    'category',
    parsedQuery,
    categoryOptions.map(option => option.id),
  )
}

export function getValidTaskFromParsedQuery(parsedQuery: SearchResults['parsedQuery']) {
  return getValidFilterValueFromParsedQuery(
    'task',
    parsedQuery,
    taskOptions.map(option => option.id),
  )
}

export function getValidPublisherFromParsedQuery(parsedQuery: SearchResults['parsedQuery']) {
  return getValidFilterValueFromParsedQuery('publisher', parsedQuery, publisherOptions)
}

export function getValidSortFromParsedQuery(parsedQuery: SearchResults['parsedQuery']) {
  return getValidFilterValueFromParsedQuery('sort', parsedQuery, Object.keys(sortOptions))
}
