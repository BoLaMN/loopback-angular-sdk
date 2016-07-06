{ isEmpty, includes, compact, clone } = require 'lodash'

module.exports = (app, opts = {}) ->
  root = app.get 'restApiRoot'
  { adapter } = app.handler 'rest'

  deepSet = (models, path, action, modelName) ->
    properties = path.split '.'

    currentObject = models[modelName]
    lastObject = currentObject

    currentRelations = app.models[modelName].relations

    embeds = []

    while properties.length
      property = properties.shift()

      if not currentObject
        break

      currentObject[property] ?= {}

      if property not in [ 'scopes', 'methods', 'aliases', 'url' ]
        if currentRelations[property]?.modelTo
          rel = currentRelations[property]

          if rel.embed and not includes lastObject.embeds, rel.keyFrom
            lastObject.embeds ?= []
            lastObject.embeds.push rel.keyFrom

      if not properties.length
        action.params.id = '@id'

        currentObject[property] = action

      lastObject = currentObject
      currentObject = currentObject[property]

    models

  reducer = (models, route) ->
    method = adapter.getRestMethodByName route.method
    modelName = method.restClass.name

    models[modelName] ?= {}

    if /create/.test method.name
      createMany = Object.create(method)
      createMany.name = createMany.name.replace('create', 'createMany')
      createMany.isReturningArray = ->
        true

      method.restClass.methods.push createMany

    if method.name is 'find'
      models[modelName].url = root + route.path + '/:id'

    action =
      url: root + route.path
      method: route.verb
      params: {}

    if method.isReturningArray()
      action.isArray = true

    method.accepts.forEach (arg) ->
      if not arg.http
        return

      if arg.http.source is 'path'
        action.params[arg.arg] = '@' + arg.arg

    method.sharedMethod.aliases.forEach (alias) ->
      models[modelName].aliases ?= {}
      models[modelName].aliases[alias] = method.name

    if method.sharedMethod.isStatic
      models[modelName].methods ?= {}
      models[modelName].methods[method.name] = action

      if createMany
        models[modelName].methods[createMany.name] = action
    else
      arr = method.sharedMethod.name.replace /__/g, ' '
      arrParts = compact arr.split ' '
      prop = arrParts[0]

      if arrParts.length > 1
        arrParts.shift()

      # console.log modelName, arrParts

      arrParts = arrParts.join '.scopes.'

      strObject = 'scopes.' + arrParts + '.methods.'
      deepSet models, strObject + prop, action, modelName

      if createMany
        deepSet models, strObject + 'createMany', action, modelName
    models

  host = app.get 'host'
  port = app.get 'port'

  servicesJS =
    models: adapter.allRoutes().reduce reducer, {}
    url: 'http://' + host + ':' + port

  configJSON = JSON.stringify servicesJS, null, '\t'

  """
    angular.module('#{ opts.name or (app.get('serverName') + '.services') }', [ 'loopback.provider' ])

    .config(["LoopBackResourceProvider", function(LoopBackResourceProvider) {
      LoopBackResourceProvider.setConfig(#{configJSON});
    }]);
  """
