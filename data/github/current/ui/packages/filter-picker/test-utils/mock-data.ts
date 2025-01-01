import {type DefaultBodyType, delay, http, HttpResponse, type StrictRequest} from 'msw'

import type {ItemConfig} from '../types'

export interface Fruit {
  id: number
  name: string
}

export const fruitItemConfig: ItemConfig<Fruit> = {
  getSearchUrl: query => `/fruities/picker/search?q=${query}`,
  onRenderItemName: country => country.name,
  itemName: 'fruit',
  itemsName: 'fruits',
  listTitle: 'Fruits list',
}

const fruitNames = [
  'Apple',
  'Apricot',
  'Avocado',
  'Banana',
  'Blackberry',
  'Blueberry',
  'Cherry',
  'Clementine',
  'Coconut',
]

export const sampleFruits = fruitNames.map((name, i) => ({id: i + 1, name}) as Fruit)
export const numerousFruits = Array.from({length: 2345}, (_, i) => ({id: i + 1, name: `fruit-${i + 1}`}) as Fruit)

export const handlers = {
  success: [http.get(`/fruities/picker/search`, getSearchHandler(sampleFruits))],
  numerousFruits: [http.get(`/fruities/picker/search`, getSearchHandler(numerousFruits))],
  error: [http.get(`/fruities/picker/search`, notFoundHandler)],
  loading: [http.get(`/fruities/picker/search`, infiniteDelayHandler)],
}

function getSearchHandler(allItems: Fruit[]) {
  return ({request}: {request: StrictRequest<DefaultBodyType>}) => {
    const url = new URL(request.url, window.location.origin)
    const q = url.searchParams.get('q')
    const items = q ? allItems.filter(item => item.name.includes(q)) : allItems
    return HttpResponse.json({items: items.slice(0, 100), totalCount: items.length})
  }
}

function notFoundHandler() {
  return new HttpResponse('Not found', {status: 404})
}

function infiniteDelayHandler() {
  return delay('infinite')
}
