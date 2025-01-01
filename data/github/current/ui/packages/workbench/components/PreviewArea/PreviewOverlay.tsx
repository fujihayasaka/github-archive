import {clsx} from 'clsx'
import {useEffect, useState} from 'react'

import {SparkleSpinner} from '../SparkleSpinner'
import {CanvasParticles} from './CanvasParticles'
import styles from './PreviewOverlay.module.css'

const MESSAGES = [
  // Original messages
  "Cookin' up something good",
  'Making magic happen',
  'Searching for greatness',

  // App building themed
  'Teaching robots new tricks',
  'Translating human to computer',
  'Sprinkling in some artificial intelligence',
  'Assembling digital building blocks',
  'Putting the micro in micro apps',
  'Building tiny tech titans',
  'Crafting code confections',
  'Miniaturizing mighty ideas',
  'Democratizing development',

  // Playful tech references
  'Consulting the silicon oracle',
  'Downloading inspiration',
  'Reticulating digital splines',
  'Gathering ones and zeros',
  'Converting caffeine to code',
  'Herding binary cats',
  'Untangling spaghetti code',
  'Debugging rubber ducks',
  'Optimizing quantum uncertainty',
  'Defragmenting imagination',
  'Compiling creative thoughts',

  // Creative process themed
  'Brainstorming with the machines',
  'Mixing imagination with algorithms',
  'Crafting digital experiences',
  'Weaving code and creativity',
  'Brewing up brilliant solutions',
  'Painting with pixels',
  'Sculpting in silicon',
  'Orchestrating binary symphonies',
  'Choreographing computational ballet',
  'Dreaming in digital',

  // Natural language themed
  'Decoding your wishes',
  'Teaching computers to speak human',
  'Turning words into wonders',
  'Processing prose into programs',
  'Transforming talk into tech',
  'Translating thoughts to things',
  'Converting conversations to code',
  'Whispering to the machines',
  'Bridging human-computer small talk',
  'Making bits and bytes bilingual',

  // Pop culture references
  'Charging flux capacitor',
  'Engaging hyperdrive',
  'Summoning digital wizards',
  'Powering up the matrix',
  'Initiating awesome sequence',
  'Asking HAL nicely',
  'Consulting Deep Thought',
  'Warming up the holodeck',
  'Rolling natural 20s',
  'Fetching coffee for the AI',

  // Internet culture & memes
  'Teaching AI to high five',
  'Downloading more RAM',
  'Feeding the coding ninjas',
  'Catching all the bugs',
  'Generating random excuses',
  'Researching blockchain buzzwords',
  'Mining digital gold',

  // Food & cooking themed
  'Baking bits and bytes',
  'Simmering solutions',
  'Stirring the code soup',
  'Adding a pinch of AI',
  'Following grandma’s secret algorithm',
  'Marinating in machine learning',

  // Nature & science themed
  'Growing digital gardens',
  'Calculating butterfly effects',
  'Observing code evolution',
  'Applying Murphy’s Law fixes',
  'Channeling quantum inspiration',
  'Dividing by zero (safely)',

  // Music themed
  'Tuning the algorithms',
  'Composing code harmonies',
  'Synchronizing binary beats',
  'Dropping the bass (case)',
  'Mixing the perfect batch',

  // Weather themed
  'Forecasting feature weather',
  'Generating idea storms',
  'Cloud computing (literally)',
  'Waiting for lightning inspiration',
  'Broadcasting good vibes',

  // More
  'Searching for aha moments',
  'Strolling through latent space',
  'Reseeding the RNG',
  'Calibrating weirdness',
  'Unrolling infinite loops',
  'Recursing and recursing and',
  'Aligning voxels',
  'Rerolling until inspiration strikes',
  'Convolving creative constructs',
  'Hill climbing towards fun',
  'Hypertuning hyperparameters',
  'Reprompting metaprompts',
  'Solving the halting problem',
  'Dodging off-by-one errors',
  'Centralizing edge cases',
  'Repainting the bikeshed',
  'Validating invalid assumptions',
  'Overloading operators',
  'Shaving a yak',
]

function LoadingDots({message}: {message: string}) {
  return (
    <div className={styles.loadingDots}>
      {message}
      <span className="dot" style={{'--i': '0'}}>
        .
      </span>
      <span className="dot" style={{'--i': '1'}}>
        .
      </span>
      <span className="dot" style={{'--i': '2'}}>
        .
      </span>
    </div>
  )
}

export function PreviewOverlay({isLoading}: {isLoading: boolean}) {
  const [message, setMessage] = useState(MESSAGES[0])
  const [isVisible, setIsVisible] = useState(false)

  useEffect(() => {
    const usedMessages = new Set([message])
    const interval = setInterval(() => {
      const availableMessages = MESSAGES.filter(msg => !usedMessages.has(msg))
      const newMessage = availableMessages[Math.floor(Math.random() * availableMessages.length)]
      usedMessages.add(newMessage)
      if (usedMessages.size === MESSAGES.length) {
        usedMessages.clear()
        usedMessages.add(newMessage)
      }
      setMessage(newMessage)
    }, 5100)

    return () => clearInterval(interval)
  }, [message])

  useEffect(() => {
    setIsVisible(isLoading)
  }, [isLoading])

  return (
    <div
      className={clsx(styles.motion, {
        [styles.motionVisible]: isVisible,
      })}
    >
      <CanvasParticles />
      <div className={styles.sparkleSpinnerContainer}>
        <SparkleSpinner />
        <LoadingDots message={message!} />
      </div>
    </div>
  )
}
