const { assertRevert } = require('@aragon/test-helpers/assertThrow')
const { getNewProxyAddress } = require('@aragon/test-helpers/events')

const { deployDao } = require('./helpers/deploy.js')(artifacts)


const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

contract('NFTSample', ([_, root, holder, someone]) => {
  
})
