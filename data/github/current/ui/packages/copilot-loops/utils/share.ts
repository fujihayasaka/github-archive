import type {Pipeline} from '../types/app'
import {compressToEncodedURIComponent, decompressFromEncodedURIComponent} from 'lz-string'

/**
 * Creates fields to copy from a loop for sharing
 *
 * @param loop - The loop to extract sharing fields from
 * @returns Object with fields suitable for sharing
 */
export function createShareableLoop(loop: Pipeline) {
  return {
    title: loop.title,
    description: loop.description,
    nodes: loop.nodes,
  }
}

/**
 * Creates a shareable URL for a loop with compression
 *
 * @param loop - The loop to create a share URL for
 * @returns A shareable URL containing the compressed loop data
 */
export function createShareUrl(loop: Pipeline): string {
  const fieldsToShare = createShareableLoop(loop)

  // Create a compressed URL-safe string of the loop JSON
  const pipelineJson = JSON.stringify(fieldsToShare)
  const compressedLoop = compressToEncodedURIComponent(pipelineJson)
  const baseUrl = window.location.origin

  return `${baseUrl}/copilot/loop/share?data=${compressedLoop}`
}

/**
 * Decodes a shared loop from the encoded data with backwards compatibility
 * Supports both compressed (lz-string) and legacy (base64) formats
 *
 * @param encodedData - The encoded loop data (compressed or base64)
 * @returns The decoded loop data or null if invalid
 */
export function decodeSharedLoop(encodedData: string): Partial<Pipeline> | null {
  try {
    // First try to decompress using lz-string (new format)
    const decompressed = decompressFromEncodedURIComponent(encodedData)
    if (decompressed) {
      const loopData = JSON.parse(decompressed) as Partial<Pipeline>

      if (!loopData.title || !loopData.nodes) {
        return null
      }

      return loopData
    }
  } catch {
    // Fall through to try legacy format
  }

  try {
    // Fall back to legacy base64 decoding for backwards compatibility
    const loopJson = decodeURIComponent(atob(encodedData))
    const loopData = JSON.parse(loopJson) as Partial<Pipeline>

    if (!loopData.title || !loopData.nodes) {
      return null
    }

    return loopData
  } catch {
    return null
  }
}

/**
 * Creates a new loop from shared loop data
 *
 * @param loopData - The partial loop data from a shared URL
 * @returns A complete Pipeline object
 */
export function createLoopFromShared(loopData: Partial<Pipeline>): Pipeline {
  const newLoopId = crypto.randomUUID()

  return {
    id: newLoopId,
    title: loopData.title ?? 'Shared Loop',
    description: loopData.description || '',
    nodes: loopData.nodes || [],
    updatedAt: new Date().toISOString(),
  }
}
