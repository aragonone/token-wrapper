import React, { useCallback } from 'react'
import PropTypes from 'prop-types'
import {
  ContextMenu,
  ContextMenuItem,
  DataView,
  IconLabel,
  IconRemove,
  GU,
  useTheme,
} from '@aragon/ui'
import { useAragonApi, useConnectedAccount } from '@aragon/api-react'
import LocalIdentityBadge from '../components/LocalIdentityBadge/LocalIdentityBadge'
import You from '../components/You'
import { useIdentity } from '../components/IdentityManager/IdentityManager'
import { addressesEqual } from '../web3-utils'

function Holders({ holders, onUnwrapTokens }) {
  const connectedAccount = useConnectedAccount()
  const { appState } = useAragonApi()
  const { wrappedTokenSymbol } = appState

  return (
    <DataView
      fields={['Holder', 'Wrapped tokens balance']}
      entries={holders}
      renderEntry={({ account, amount }) => {
        const isCurrentUser = addressesEqual(account, connectedAccount)
        return [
          <div>
            <LocalIdentityBadge
              entity={account}
              connectedAccount={isCurrentUser}
            />
            {isCurrentUser && <You />}
          </div>,
          <div>
            {amount} {wrappedTokenSymbol}
          </div>,
        ]
      }}
      renderEntryActions={({ account, amount }) => {
        return [
          <EntryActions onUnwrapTokens={onUnwrapTokens} address={account} />,
        ]
      }}
    />
  )
}

Holders.propTypes = {
  holders: PropTypes.array,
}

Holders.defaultProps = {
  holders: [],
}

function EntryActions({ onUnwrapTokens, address }) {
  const theme = useTheme()
  const connectedAccount = useConnectedAccount()
  const [label, showLocalIdentityModal] = useIdentity(address)

  const isCurrentUser = addressesEqual(address, connectedAccount)
  const editLabel = useCallback(() => showLocalIdentityModal(address), [
    address,
    showLocalIdentityModal,
  ])

  const actions = [
    ...(isCurrentUser ? [[onUnwrapTokens, IconRemove, 'Unwrap tokens']] : []),
    [editLabel, IconLabel, `${label ? 'Edit' : 'Add'} custom label`],
  ]
  return (
    <ContextMenu>
      {actions.map(([onClick, Icon, label], index) => (
        <ContextMenuItem onClick={onClick} key={index}>
          <span
            css={`
              position: relative;
              display: flex;
              align-items: center;
              justify-content: center;
              color: ${theme.surfaceContentSecondary};
            `}
          >
            <Icon />
          </span>
          <span
            css={`
              margin-left: ${1 * GU}px;
            `}
          >
            {label}
          </span>
        </ContextMenuItem>
      ))}
    </ContextMenu>
  )
}

export default Holders
