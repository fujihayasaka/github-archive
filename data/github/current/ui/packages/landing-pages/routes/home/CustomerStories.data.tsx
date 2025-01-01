import CustomerStoriesFigmaBackground from './assets/customer-stories/backgrounds/figma.webp'
import CustomerStoriesMercedesBenzBackground from './assets/customer-stories/backgrounds/mercedes-benz.webp'
import CustomerStoriesMercadoLibreBackground from './assets/customer-stories/backgrounds/mercado-libre.webp'
import CustomerStoriesAccentureBackground from './assets/customer-stories/backgrounds/accenture.webp'
import CustomerStoriesPhilipsBackground from './assets/customer-stories/backgrounds/philips.webp'
import CustomerStoriesBufferBackground from './assets/customer-stories/backgrounds/buffer.webp'
import CustomerStoriesTelusBackground from './assets/customer-stories/backgrounds/telus.webp'
import CustomerStoriesFullstoryBackground from './assets/customer-stories/backgrounds/fullstory.webp'
import CustomerStoriesEYBackground from './assets/customer-stories/backgrounds/ey.webp'

import CustomerStoriesFigmaLogo from './assets/customer-stories/logos/figma.svg'
import CustomerStoriesMercedesBenzLogo from './assets/customer-stories/logos/mercedes-benz.svg'
import CustomerStoriesMercadoLibreLogo from './assets/customer-stories/logos/mercado-libre.svg'
import CustomerStoriesAccentureLogo from './assets/customer-stories/logos/accenture.svg'
import CustomerStoriesPhilipsLogo from './assets/customer-stories/logos/philips.svg'
import CustomerStoriesBufferLogo from './assets/customer-stories/logos/buffer.svg'
import CustomerStoriesTelusLogo from './assets/customer-stories/logos/telus.svg'
import CustomerStoriesFullstoryLogo from './assets/customer-stories/logos/fullstory.svg'
import CustomerStoriesEYLogo from './assets/customer-stories/logos/ey.svg'

export const StoryCategory = {
  Industry: 0,
  Size: 1,
  UseCase: 2,
} as const

export type StoryCategory = (typeof StoryCategory)[keyof typeof StoryCategory]

export const IndustrySubCategory = {
  Technology: 0,
  Automotive: 1,
  Financial: 2,
} as const

export type IndustrySubCategory = (typeof IndustrySubCategory)[keyof typeof IndustrySubCategory]

export const SizeSubCategory = {
  Enterprises: 3,
  Teams: 4,
  Startups: 5,
} as const

export type SizeSubCategory = (typeof SizeSubCategory)[keyof typeof SizeSubCategory]

export const UseCaseSubCategory = {
  DevSecOps: 6,
  Automation: 7,
  DevOps: 8,
} as const

export type UseCaseSubCategory = (typeof UseCaseSubCategory)[keyof typeof UseCaseSubCategory]

export type StorySubCategory = IndustrySubCategory | SizeSubCategory | UseCaseSubCategory

interface CustomerStory {
  category: StoryCategory
  subCategory: StorySubCategory
  description: string
  url: string
  backgroundUrl: string
  logo: {
    url: string
    alt: string
    height?: string
  }
}

type CustomerStoryData = Omit<CustomerStory, 'category' | 'subCategory' | 'url'>

type SubCategoryDictionaryData = Record<string, CustomerStoryData>
type SubCategoryDictionary = Record<string, CustomerStory>
type CustomerStoryDictionary = Record<StoryCategory, Partial<Record<StorySubCategory, SubCategoryDictionary>>>
type CustomerStoryDataDictionary = Record<StoryCategory, Partial<Record<StorySubCategory, SubCategoryDictionaryData>>>

const technologyStories: SubCategoryDictionaryData = {
  figma: {
    description: 'Figma streamlines development and strengthens security',
    backgroundUrl: CustomerStoriesFigmaBackground,
    logo: {
      alt: 'Figma',
      height: '35px',
      url: CustomerStoriesFigmaLogo,
    },
  },
}

const automotiveStories: SubCategoryDictionaryData = {
  mercedesBenz: {
    description: 'Mercedes-Benz standardizes source code and automates onboarding',
    backgroundUrl: CustomerStoriesMercedesBenzBackground,
    logo: {
      alt: 'Mercedes-Benz',
      height: '48px',
      url: CustomerStoriesMercedesBenzLogo,
    },
  },
}

const financialStories: SubCategoryDictionaryData = {
  mercadoLibre: {
    description: 'Mercado Libre cuts coding time by 50%',
    backgroundUrl: CustomerStoriesMercadoLibreBackground,
    logo: {
      alt: 'Mercado Libre',
      height: '40px',
      url: CustomerStoriesMercadoLibreLogo,
    },
  },
}

const enterprisesStories: SubCategoryDictionaryData = {
  accenture: {
    description: 'Accenture customizes GitHub Copilot for its 12,000 developers',
    backgroundUrl: CustomerStoriesAccentureBackground,
    logo: {
      alt: 'Accenture',
      height: '36px',
      url: CustomerStoriesAccentureLogo,
    },
  },
  philips: {
    description: 'Philips reduces infrastructure costs by 80%',
    backgroundUrl: CustomerStoriesPhilipsBackground,
    logo: {
      alt: 'Philips’ logo',
      height: '34px',
      url: CustomerStoriesPhilipsLogo,
    },
  },
}

const teamsStories: SubCategoryDictionaryData = {
  buffer: {
    description: 'Buffer enhances collaboration and control with GitHub Team',
    backgroundUrl: CustomerStoriesBufferBackground,
    logo: {
      alt: 'Buffer',
      height: '32px',
      url: CustomerStoriesBufferLogo,
    },
  },
}

const devSecOpsStories: SubCategoryDictionaryData = {
  telus: {
    description: 'TELUS saves $16.9M with GitHub',
    backgroundUrl: CustomerStoriesTelusBackground,
    logo: {
      alt: 'Telus’ logo',
      height: '36px',
      url: CustomerStoriesTelusLogo,
    },
  },
}

const automationStories: SubCategoryDictionaryData = {
  fullstory: {
    description: 'Fullstory automates DevSecOps at scale with GitHub',
    backgroundUrl: CustomerStoriesFullstoryBackground,
    logo: {
      alt: 'Fullstory',
      height: '36px',
      url: CustomerStoriesFullstoryLogo,
    },
  },
}

const devOpsStories: SubCategoryDictionaryData = {
  ey: {
    description: 'EY leverages GitHub and Microsoft Azure DevOps to outpace the competition',
    backgroundUrl: CustomerStoriesEYBackground,
    logo: {
      alt: 'EY',
      height: '52px',
      url: CustomerStoriesEYLogo,
    },
  },
}

const customerStoriesData: CustomerStoryDataDictionary = {
  [StoryCategory.Industry]: {
    [IndustrySubCategory.Technology]: technologyStories,
    [IndustrySubCategory.Automotive]: automotiveStories,
    [IndustrySubCategory.Financial]: financialStories,
  },
  [StoryCategory.Size]: {
    [SizeSubCategory.Enterprises]: enterprisesStories,
    [SizeSubCategory.Teams]: teamsStories,
  },
  [StoryCategory.UseCase]: {
    [UseCaseSubCategory.DevSecOps]: devSecOpsStories,
    [UseCaseSubCategory.Automation]: automationStories,
    [UseCaseSubCategory.DevOps]: devOpsStories,
  },
}

const BASE_URL = 'https://github.com/customer-stories'

const toKebabCase = (string: string) => {
  return string
    .replace(/([a-z])([A-Z])/g, '$1-$2') // Insert dash between lowercase and uppercase letters
    .replace(/([A-Z])([A-Z][a-z])/g, '$1-$2') // Handle cases like 'XMLHttpRequest'
    .toLowerCase() // Convert all to lowercase
}

export const CUSTOMER_STORIES = {} as CustomerStoryDictionary

// eslint-disable-next-line github/array-foreach
Object.entries(customerStoriesData).forEach(([category, subCategories]) => {
  const typedCategory = Number(category) as StoryCategory
  if (!CUSTOMER_STORIES[typedCategory]) CUSTOMER_STORIES[typedCategory] = {}

  // eslint-disable-next-line github/array-foreach
  Object.entries(subCategories).forEach(([subCategory, stories]) => {
    const typedSubCategory = Number(subCategory) as StorySubCategory

    if (!CUSTOMER_STORIES[typedCategory][typedSubCategory]) CUSTOMER_STORIES[typedCategory][typedSubCategory] = {}

    // eslint-disable-next-line github/array-foreach
    Object.entries(stories).forEach(([customerId, story]) => {
      const parsedCustomerId = toKebabCase(customerId)

      // @ts-expect-error The object is correctly initialized above
      CUSTOMER_STORIES[typedCategory][typedSubCategory][customerId] = {
        ...story,
        category: typedCategory,
        subCategory: typedSubCategory,
        url: `${BASE_URL}/${parsedCustomerId}`,
      }
    })
  })
})

export const COPY = {
  analyticsId: 'customer_stories',
  intro: {
    title:
      'From startups to enterprises, <span>GitHub scales <br class="lp-breakText" /> with teams of any size in any industry.</span>',
  },
  content: {
    categories: {
      [StoryCategory.Industry]: 'By industry',
      [StoryCategory.Size]: 'By size',
      [StoryCategory.UseCase]: 'By use case',
    },
    subCategories: {
      [IndustrySubCategory.Technology]: 'Technology',
      [IndustrySubCategory.Automotive]: 'Automotive',
      [IndustrySubCategory.Financial]: 'Financial services',
      [SizeSubCategory.Enterprises]: 'Enterprises',
      [SizeSubCategory.Teams]: 'Teams',
      [SizeSubCategory.Startups]: 'Startups',
      [UseCaseSubCategory.DevSecOps]: 'DevSecOps',
      [UseCaseSubCategory.Automation]: 'Automation',
      [UseCaseSubCategory.DevOps]: 'DevOps',
    },
    readMore: 'Read customer story',
    aria: {
      // TODO: Update once known
      toggle: '',
    },
  },
  links: [
    {
      url: '/customer-stories',
      label: 'Explore customer stories',
    },
    {
      url: '/solutions',
      label: 'View all solutions',
    },
  ],
}
