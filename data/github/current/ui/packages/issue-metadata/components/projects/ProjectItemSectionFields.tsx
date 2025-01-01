/* eslint eslint-comments/no-use: off */
/* eslint-disable relay/unused-fields */
import {graphql, useFragment} from 'react-relay'
import {useMemo} from 'react'
import {SingleSelectField} from './fields/SingleSelectField'
import {TextField} from './fields/TextField'
import {NumberField} from './fields/NumberField'
import {IterationField} from './fields/IterationField'
import {DateField} from './fields/DateField'
import type {ProjectItemSectionFields$key} from './__generated__/ProjectItemSectionFields.graphql'
import type {ProjectItemSectionFieldsValues$key} from './__generated__/ProjectItemSectionFieldsValues.graphql'
import styles from './ProjectsSections.module.css'
import {clsx} from 'clsx'

type ProjectItemSectionFieldsProps = {
  projectItem: ProjectItemSectionFields$key
  onIssueUpdate?: () => void
}

const ProjectItemSectionFieldsFragment = graphql`
  fragment ProjectItemSectionFields on ProjectV2Item {
    id
    isArchived
    project {
      id
      title
      url
      viewerCanUpdate
      fields(first: 50, orderBy: {field: POSITION, direction: ASC}) {
        edges {
          node {
            ... on ProjectV2Field {
              id
              dataType
              name
              ...TextFieldConfigFragment @dangerously_unaliased_fixme
              ...DateFieldConfigFragment @dangerously_unaliased_fixme
              ...NumberFieldConfigFragment @dangerously_unaliased_fixme
            }
            ... on ProjectV2IterationField {
              id
              dataType
              name
              ...IterationFieldConfigFragment @dangerously_unaliased_fixme
            }
            ... on ProjectV2SingleSelectField {
              id
              dataType
              name
              ...SingleSelectFieldConfigFragment @dangerously_unaliased_fixme
            }
          }
        }
      }
    }
    ...ProjectItemSectionFieldsValues
  }
`

export function ProjectItemSectionFields({projectItem, onIssueUpdate}: ProjectItemSectionFieldsProps) {
  const projectItemFields = useFragment(ProjectItemSectionFieldsFragment, projectItem)

  const {fieldValues} = useFragment<ProjectItemSectionFieldsValues$key>(
    graphql`
      fragment ProjectItemSectionFieldsValues on ProjectV2Item {
        fieldValues(first: 50, orderBy: {field: POSITION, direction: ASC})
          @connection(key: "ProjectItemSection_fieldValues") {
          edges {
            node {
              ... on ProjectV2ItemFieldTextValue {
                id
                field {
                  ... on ProjectV2Field {
                    id
                  }
                }
              }
              ...TextFieldFragment @dangerously_unaliased_fixme
              ... on ProjectV2ItemFieldNumberValue {
                id
                field {
                  ... on ProjectV2Field {
                    id
                  }
                }
              }
              ...NumberFieldFragment @dangerously_unaliased_fixme
              ... on ProjectV2ItemFieldDateValue {
                id
                field {
                  ... on ProjectV2Field {
                    id
                  }
                }
              }
              ...DateFieldFragment @dangerously_unaliased_fixme
              ... on ProjectV2ItemFieldSingleSelectValue {
                id
                field {
                  ... on ProjectV2SingleSelectField {
                    id
                  }
                }
              }
              ...SingleSelectFieldFragment @dangerously_unaliased_fixme
              ... on ProjectV2ItemFieldIterationValue {
                id
                field {
                  ... on ProjectV2IterationField {
                    id
                  }
                }
              }
              ...IterationFieldFragment @dangerously_unaliased_fixme
            }
          }
        }
      }
    `,
    projectItemFields,
  )

  const fields = useMemo(
    () =>
      (projectItemFields?.project.fields?.edges || [])
        .map(edge => {
          if (!edge?.node || edge.node.name === 'Status') {
            return
          }

          const field = edge.node
          const dataType = field.dataType

          const fieldId = field.id
          const value =
            (fieldValues?.edges || []).flatMap(e => (e?.node ? [e.node] : [])).find(e => e?.field?.id === fieldId) ||
            null

          const props = {
            key: fieldId,
            viewerCanUpdate: !projectItemFields.isArchived && projectItemFields.project.viewerCanUpdate,
            itemId: projectItemFields.id,
            projectId: projectItemFields.project.id,
            field,
            value,
            onIssueUpdate,
          }

          switch (dataType) {
            case 'SINGLE_SELECT':
              return <SingleSelectField {...props} key={props.key} />
            case 'TEXT':
              return <TextField {...props} key={props.key} />
            case 'DATE':
              return <DateField {...props} key={props.key} />
            case 'NUMBER':
              return <NumberField {...props} key={props.key} />
            case 'ITERATION':
              return <IterationField {...props} key={props.key} />
          }
        })
        .filter(i => i !== undefined),
    [
      projectItemFields.project.fields?.edges,
      projectItemFields.project.viewerCanUpdate,
      projectItemFields.project.id,
      projectItemFields.isArchived,
      projectItemFields.id,
      fieldValues?.edges,
      onIssueUpdate,
    ],
  )

  return fields.length === 0 ? (
    <> </>
  ) : (
    <ul className={clsx(styles.FieldListUl, styles.FieldListInternal)}>
      {fields.map((field, index) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <li className={styles.FieldListLi} key={`project-field-${index}`}>
          {field}
        </li>
      ))}
    </ul>
  )
}
