import type {NodeType, Node} from '../types/app'

export function buildNewNode(type: NodeType, id: string, title: string, description: string): Node {
  const commonNodeFields = {
    content: '',
    id,
    title,
    description,
  }

  switch (type) {
    case 'loop':
      return {
        ...commonNodeFields,
        type,
        loopId: '',
      }
    case 'text':
      return {
        ...commonNodeFields,
        type,
        inputType: {
          type: 'text',
        },
      }
    default:
      return {
        ...commonNodeFields,
        type,
      }
  }
}
