import {PlusIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, FormControl, IconButton, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import type {NodeType} from '../../types/app'
import {nodeHandlerRegistry} from '../../service/node-handler-registry'
import type {NodeHandlerMetadata} from '../../types/node-handler-interface'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {useLoopOperations} from '../../hooks/use-loop-operations'
import {buildNewNode} from '../../utils/nodes'
import {useState} from 'react'
import styles from './AddNodeButton.module.css'
import {useNodeIDs} from '../../state/lenses'
import {useLoop} from '../../hooks/queries/use-loop'

/**
 * Temporary dialog so users can add nodes with custom titles and descriptions.
 * This will be removed once we have a better UI for editing nodes.
 */
function AddNodeDialog({
  onClose,
  onConfirm,
}: {
  onClose: () => void
  onConfirm: (title: string, description: string) => void
}) {
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')

  return (
    <Dialog title="Add Node" onClose={onClose}>
      <Dialog.Header>Add a new node to your pipeline</Dialog.Header>
      <Dialog.Body className={styles.dialogBody}>
        <FormControl>
          <FormControl.Label>Node Title</FormControl.Label>
          <TextInput value={title} onChange={e => setTitle(e.target.value)} placeholder="New node" />
        </FormControl>
        <FormControl>
          <FormControl.Label>Node Description</FormControl.Label>
          <TextInput
            value={description}
            onChange={e => setDescription(e.target.value)}
            placeholder="New node description"
          />
        </FormControl>
      </Dialog.Body>
      <Dialog.Footer>
        <Button onClick={onClose}>Cancel</Button>
        <Button onClick={() => onConfirm(title, description)} variant="primary">
          Confirm
        </Button>
      </Dialog.Footer>
    </Dialog>
  )
}

function AddNodeListItem({nodeType, onSelect}: {nodeType: NodeHandlerMetadata; onSelect: (type: NodeType) => void}) {
  const Icon = nodeType.icon()

  return (
    <ActionList.Item onSelect={() => onSelect(nodeType.type)}>
      <ActionList.LeadingVisual>
        <Icon />
      </ActionList.LeadingVisual>
      {nodeType.label()}
      <ActionList.Description variant="block">{nodeType.description()}</ActionList.Description>
    </ActionList.Item>
  )
}

export function AddNodeButton() {
  const featureFlags = useFeatureFlags()
  const {data: loop} = useLoop()
  const nodeIDs = useNodeIDs()
  const {addNode} = useLoopOperations()
  const [selectedNodeTypeToAdd, setSelectedNodeTypeToAdd] = useState<NodeType>()

  const nodeTypeList = nodeHandlerRegistry.getAllMetadata()
  const enabledNodeTypes = nodeTypeList.reduce((flags, nodeType) => {
    if (!nodeType.featureFlag || featureFlags[nodeType.featureFlag]) {
      flags.push(nodeType)
    }

    return flags
  }, [] as NodeHandlerMetadata[])

  const handleAddNode = (nodeType: NodeType, nodeTitle: string, nodeDescription: string) => {
    if (!loop) return

    const maxId = nodeIDs.reduce((currentMaxId, id) => Math.max(currentMaxId, parseInt(id)), 0)
    const nextId = (maxId + 1).toString()
    const node = buildNewNode(nodeType, nextId, nodeTitle, nodeDescription)
    addNode(node)
  }

  if (!featureFlags['copilot_loops_post_staff_ship_features']) return null

  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <IconButton aria-label="Add node" icon={PlusIcon} />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay width="small">
          <ActionList>
            {enabledNodeTypes.map(nodeType => (
              <AddNodeListItem
                key={nodeType.type}
                nodeType={nodeType}
                onSelect={() => setSelectedNodeTypeToAdd(nodeType.type)}
              />
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {selectedNodeTypeToAdd && (
        <AddNodeDialog
          onClose={() => setSelectedNodeTypeToAdd(undefined)}
          onConfirm={(title, description) => {
            handleAddNode(selectedNodeTypeToAdd, title, description)
            setSelectedNodeTypeToAdd(undefined)
          }}
        />
      )}
    </>
  )
}
