import useToasts from '../components/toasts/use-toasts'
import {useNavigate} from '../router'
import {useProjectRouteParams} from '../router/use-project-route-params'
import {PROJECT_WORKFLOW_CLIENT_ID_ROUTE} from '../routes'
import {useWorkflows} from '../state-providers/workflows/use-workflows'

export function useAutoAddSubIssueWorkflowToast() {
  const navigate = useNavigate()
  const projectRouteParams = useProjectRouteParams()
  const {workflows} = useWorkflows()
  const {addToast} = useToasts()

  function showAutoAddSubIssueToast() {
    const autoAddSubIssueWorkflow = workflows.find(w => w.name === 'Auto-add sub-issues to project')

    if (!autoAddSubIssueWorkflow?.enabled) return

    // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
    addToast({
      message:
        'Sub-issues will be automatically added to your project. Prefer to disable this? Click the button below to turn off the workflow.',
      type: 'default',
      action: {
        text: 'Disable workflow',
        handleClick: () => {
          navigate(
            PROJECT_WORKFLOW_CLIENT_ID_ROUTE.generatePath({
              ...projectRouteParams,
              workflowClientId: autoAddSubIssueWorkflow.clientId,
            }),
          )
        },
      },
    })
  }

  return showAutoAddSubIssueToast
}
