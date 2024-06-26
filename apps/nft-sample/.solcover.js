module.exports = {
  norpc: true,
  copyPackages: ['@aragon/os', '@aragonone/voting-connectors-contract-utils'],
  skipFiles: [
    'examples',
    'interfaces',
    'test',
    '@aragon/os',
    '@aragonone/voting-connectors-contract-utils',
  ]
}
