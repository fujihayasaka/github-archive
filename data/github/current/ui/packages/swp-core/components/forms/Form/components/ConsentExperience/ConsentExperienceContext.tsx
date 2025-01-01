import {createContext} from 'react'
import type {Country} from './types'

interface ConsentExperienceContextType {
  marketingTargetedCountries: Country[]
}

export const ConsentExperienceContext = createContext<ConsentExperienceContextType>({
  marketingTargetedCountries: [],
})
