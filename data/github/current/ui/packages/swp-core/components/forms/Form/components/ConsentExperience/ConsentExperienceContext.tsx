import {createContext} from 'react'

export interface Country {
  name: string
  alpha: string
}

interface ConsentExperienceContextType {
  marketingTargetedCountries: Country[]
}

export const ConsentExperienceContext = createContext<ConsentExperienceContextType>({
  marketingTargetedCountries: [],
})
