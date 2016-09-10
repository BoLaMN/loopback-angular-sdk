{ isEmpty, includes, compact, clone } = require 'lodash'

modelInfo = require './model'

module.exports = (app, opts = {}) ->
  root = app.get 'restApiRoot'
  { adapter } = app.handler 'rest'

  deepSet = (models, properties, newProp, action, modelName) ->
    currentObject = models[modelName]
    lastObject = currentObject

    currentRelations = app.models[modelName].relations

    embeds = []

    properties.push newProp

    while properties.length
      property = properties.shift()

      if not currentObject
        break

      currentObject[property] ?= {}

      if property not in [ 'scopes', 'methods', 'aliases', 'url' ]
        if currentRelations[property]?.modelTo
          rel = currentRelations[property]

          modelTo = rel.modelTo

          currentObject[property].model = modelTo.modelName

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
    models[modelName].properties = modelInfo app.models[modelName]

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
      models[modelName].aliases[alias] = method.name.replace 'prototype.', ''

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

      if prop is arrParts[0]
        models[modelName].methods ?= {}
        action.params.id = '@id'
        models[modelName].methods[prop] = action
      else
        arrParts = arrParts.join '.scopes.'
        arrObject = [ 'scopes' ].concat(arrParts.split('.')).concat [ 'methods' ]

        deepSet models, arrObject, prop, action, modelName

        if createMany
          deepSet models, arrObject, 'createMany', action, modelName
    models

  servicesJS =
    models: adapter.allRoutes().reduce reducer, {}

  configJSON = JSON.stringify servicesJS, null, '\t'

  """
    angular.module('#{ opts.name or (app.get('serverName') + '.services') }', [ 'loopback.sdk' ])

    .config(["ResourceProvider", function(ResourceProvider) {
      ResourceProvider.setConfig(#{configJSON});
    }]);
  """
