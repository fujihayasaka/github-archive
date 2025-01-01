import {createContext} from 'react'
import type {useForm} from './hooks/useForm'

export const FormContext = createContext<ReturnType<typeof useForm> | undefined>(undefined)
