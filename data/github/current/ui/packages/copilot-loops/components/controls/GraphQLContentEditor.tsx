import {ContentEditorWithAutocomplete} from './ContentEditorWithAutocomplete'
import {autocompletion} from '@codemirror/autocomplete'
import type {Extension} from '@codemirror/state'
import {useEffect, useState} from 'react'

/**
 * Hook to fetch the GraphQL schema using introspection query.
 * Returns the built GraphQL schema or undefined if loading/error.
 *
 * TODO: Figure out how to load schema more efficiently.
 */
// function useGraphQLSchema() {
//   const pipesService = usePipesService()

//   const {data: graphqlResponse} = useQuery({
//     queryKey: ['graphql-schema-introspection'],
//     queryFn: async () => {
//       const introspectionQuery = getIntrospectionQuery()
//       return pipesService.getGraphQLResponse(introspectionQuery)
//     },
//     staleTime: Infinity, // Schema won't change during session
//   })

//   // Build client schema from introspection results
//   if (graphqlResponse) {
//     try {
//       const data = graphqlResponse.data
//       return buildClientSchema(data as unknown as IntrospectionQuery)
//     } catch (error) {
//       logError('Error building GraphQL schema:', error)
//     }
//   }

//   return undefined
// }

/**
 * A ContentEditor with GraphQL schema support for autocompletion and syntax highlighting.
 */
export const GraphQLContentEditor = ({
  className,
  content,
  onUpdate,
  nodeId,
  inputLabelId,
}: {
  className?: string
  content: string
  onUpdate?: (content: string) => void
  nodeId: string
  inputLabelId: string
}) => {
  // const schema = useGraphQLSchema()
  const [extensions, setExtensions] = useState<Extension[] | undefined>()

  useEffect(() => {
    // Lazy load the GraphQL extension
    const loadGraphQL = async () => {
      const {graphql} = await import('cm6-graphql')
      setExtensions([autocompletion(), graphql()])
    }
    void loadGraphQL()
  }, [])

  return (
    <ContentEditorWithAutocomplete
      className={className}
      content={content}
      extensions={extensions}
      inputLabelId={inputLabelId}
      nodeId={nodeId}
      onUpdate={onUpdate}
      placeholder="Enter a GraphQL query"
    />
  )
}
