import {readFileSync} from 'fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

const serviceNameRegex = /^\s\s(\w+):/
const teamNameRegex = /^\s\s\s\s+team:\s(.+)/

let services: string[]
let teams: Set<string>

function getServiceMappingsLines() {
  const file = readFileSync(fullPathFromRoot('config/service-mappings.yaml'), 'utf8')
  const lines = file.split('\n')

  return lines
}

function getAvailableServices() {
  if (services) {
    return services
  }
  services = []

  const lines = getServiceMappingsLines()
  for (const line of lines) {
    if (line.startsWith('review_groups:')) {
      break
    }

    const serviceName = line.match(serviceNameRegex)

    if (serviceName && serviceName[1] && serviceName[1] !== 'github') {
      services.push(serviceName[1])
    }
  }

  return Array.from(services)
}

function getAvailableTeams() {
  if (teams) {
    return Array.from(teams)
  }
  teams = new Set<string>()

  const lines = getServiceMappingsLines()
  for (const line of lines) {
    if (line.startsWith('review_groups:')) {
      break
    }

    const teamName = line.match(teamNameRegex)

    if (teamName && teamName[1] && teamName[1] !== 'github') {
      teams.add(teamName[1])
    }
  }

  return Array.from(teams)
}

export function listMatchingServices(input: string) {
  const allServices = getAvailableServices()

  if (!input) {
    return allServices
  }

  return allServices.filter(service => service.startsWith(input))
}

export function listMatchingTeams(input: string) {
  const allTeams = getAvailableTeams()

  if (!input) {
    return allTeams
  }

  return allTeams.filter(team => team.startsWith(input))
}

const serviceOwnerNameRegex = /^\S+\s+:(\S+)/
export function getServiceOwnerForFile(filePath: string) {
  const file = readFileSync(fullPathFromRoot('SERVICEOWNERS'), 'utf8')
  const lines = file.split('\n')
  const line = lines.find(l => l.startsWith(filePath))

  const match = line?.match(serviceOwnerNameRegex)
  if (match) {
    return match[1]
  }

  return null
}
