module.exports = (artifacts) => {
  const deployDao = async (owner) => {
    const ACL = artifacts.require('ACL')
    const Kernel = artifacts.require('Kernel')

    const dao = await Kernel.new(false)
    const aclBase = await ACL.new()
    await dao.initialize(aclBase.address, owner)
    const acl = ACL.at(await dao.acl())
    await acl.createPermission(owner, dao.address, await dao.APP_MANAGER_ROLE(), owner, { from: owner })

    return { dao, acl }
  }

  return {
    deployDao
  }
}
