import 'core-js/stable'
import 'regenerator-runtime/runtime'
import Aragon, { events } from '@aragon/api'

const TokenBalanceOfABI = require('./abi/token-balanceOf.json')
const TokenSymbolABI = require('./abi/token-symbol.json')

const app = new Aragon()

const initialState = async () => {
  const token = await getToken()
  const erc20 = await getERC20()
  const erc20Symbol = await getTokenSymbol(erc20)

  return {
    token,
    erc20,
    erc20Symbol,
    erc20Balance: 0,
    tokenBalance: 0,
    account: undefined
  }
}

const reducer = async (state, { event, returnValues }) => {
  let nextState = { ...state }
  const { token, erc20, account } = state

  switch (event) {
    case 'TokensLocked':
      nextState = {
        ...state,
        tokenBalance: await getTokenBalance(token, account),
        erc20Balance: await getTokenBalance(erc20, account)
      }
      break
    case 'TokensUnlocked':
      nextState = {
        ...state,
        tokenBalance: await getTokenBalance(token, account),
        erc20Balance: await getTokenBalance(erc20, account)
      }
      break
    case events.ACCOUNTS_TRIGGER:
      const newAccount = returnValues.account
      nextState = {
        ...state,
        account: newAccount,
        tokenBalance: await getTokenBalance(token, newAccount),
        erc20Balance: await getTokenBalance(erc20, newAccount)
      }
      break
    case events.SYNC_STATUS_SYNCING:
      nextState = { ...state, isSyncing: true }
      break
    case events.SYNC_STATUS_SYNCED:
      nextState = { ...state, isSyncing: false }
      break
  }

  return nextState
}

app.store(reducer, { init: initialState })

async function getToken() {
  return app.call('token').toPromise()
}

async function getERC20() {
  return app.call('erc20').toPromise()
}

async function getTokenBalance(token, account) {
  const tokenContract = app.external(token, TokenBalanceOfABI)
  return tokenContract.balanceOf(account).toPromise()
}

async function getTokenSymbol(token) {
  const tokenContract = app.external(token, TokenSymbolABI)
  return tokenContract.symbol().toPromise()
}
