import {useState, useRef} from 'react'
import {Text, Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {formatMoneyDisplay} from '../../utils/money'
import {listStyle, Fonts, Spacing} from '../../utils/style'

interface Props {
  totalUsage: number
  usageMap: Record<string, number>
}

export default function UsageOverviewListDialog({totalUsage, usageMap}: Props) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const returnFocusRef = useRef(null)

  return (
    <div data-testid="usage-overview-list-dialog-container">
      <Button variant="invisible" onClick={() => setIsDialogOpen(true)} sx={{fontSize: Fonts.FontSizeSmall}}>
        More details
      </Button>

      {isDialogOpen && (
        <Dialog
          onClose={() => setIsDialogOpen(false)}
          title="Current metered usage"
          returnFocusRef={returnFocusRef}
          aria-labelledby="header"
          sx={{overflowY: 'auto'}}
        >
          <Box sx={{p: Spacing.StandardPadding}}>
            <div>
              <Text sx={{fontSize: 4}} data-testid="total-usage">
                {formatMoneyDisplay(totalUsage)}
              </Text>
            </div>
            <ul className="mt-0 pt-0">
              {Object.entries(usageMap)
                .sort(([, valueA], [, valueB]) => valueB - valueA)
                .map(([key, value]) => {
                  return (
                    <Box as="li" sx={listStyle} key={`usage-selection-${key}`} data-testid={`usage-selection-${key}`}>
                      <Text
                        as="p"
                        sx={{
                          flex: 'auto',
                          overflow: 'auto',
                        }}
                      >
                        {key}
                      </Text>
                      <Text as="p" sx={{fontWeight: 'bold'}}>
                        {formatMoneyDisplay(value || 0)}
                      </Text>
                    </Box>
                  )
                })}
            </ul>
          </Box>
        </Dialog>
      )}
    </div>
  )
}
