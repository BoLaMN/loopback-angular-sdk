var clone, compact, includes, isEmpty, ref;

ref = require('lodash'), isEmpty = ref.isEmpty, includes = ref.includes, compact = ref.compact, clone = ref.clone;

module.exports = function(app, opts) {
  var adapter, configJSON, deepSet, host, port, reducer, root, servicesJS;
  if (opts == null) {
    opts = {};
  }
  root = app.get('restApiRoot');
  adapter = app.handler('rest').adapter;
  deepSet = function(models, path, action, modelName) {
    var currentObject, currentRelations, embeds, lastObject, properties, property, ref1, rel;
    properties = path.split('.');
    currentObject = models[modelName];
    lastObject = currentObject;
    currentRelations = app.models[modelName].relations;
    embeds = [];
    while (properties.length) {
      property = properties.shift();
      if (!currentObject) {
        break;
      }
      if (currentObject[property] == null) {
        currentObject[property] = {};
      }
      if (property !== 'scopes' && property !== 'methods' && property !== 'aliases' && property !== 'url') {
        if ((ref1 = currentRelations[property]) != null ? ref1.modelTo : void 0) {
          rel = currentRelations[property];
          if (rel.embed && !includes(lastObject.embeds, rel.keyFrom)) {
            if (lastObject.embeds == null) {
              lastObject.embeds = [];
            }
            lastObject.embeds.push(rel.keyFrom);
          }
        }
      }
      if (!properties.length) {
        action.params.id = '@id';
        currentObject[property] = action;
      }
      lastObject = currentObject;
      currentObject = currentObject[property];
    }
    return models;
  };
  reducer = function(models, route) {
    var action, arr, arrParts, base, createMany, method, modelName, prop, strObject;
    method = adapter.getRestMethodByName(route.method);
    modelName = method.restClass.name;
    if (models[modelName] == null) {
      models[modelName] = {};
    }
    if (/create/.test(method.name)) {
      createMany = Object.create(method);
      createMany.name = createMany.name.replace('create', 'createMany');
      createMany.isReturningArray = function() {
        return true;
      };
      method.restClass.methods.push(createMany);
    }
    if (method.name === 'find') {
      models[modelName].url = root + route.path + '/:id';
    }
    action = {
      url: root + route.path,
      method: route.verb,
      params: {}
    };
    if (method.isReturningArray()) {
      action.isArray = true;
    }
    method.accepts.forEach(function(arg) {
      if (!arg.http) {
        return;
      }
      if (arg.http.source === 'path') {
        return action.params[arg.arg] = '@' + arg.arg;
      }
    });
    method.sharedMethod.aliases.forEach(function(alias) {
      var base;
      if ((base = models[modelName]).aliases == null) {
        base.aliases = {};
      }
      return models[modelName].aliases[alias] = method.name;
    });
    if (method.sharedMethod.isStatic) {
      if ((base = models[modelName]).methods == null) {
        base.methods = {};
      }
      models[modelName].methods[method.name] = action;
      if (createMany) {
        models[modelName].methods[createMany.name] = action;
      }
    } else {
      arr = method.sharedMethod.name.replace(/__/g, ' ');
      arrParts = compact(arr.split(' '));
      prop = arrParts[0];
      if (arrParts.length > 1) {
        arrParts.shift();
      }
      arrParts = arrParts.join('.scopes.');
      strObject = 'scopes.' + arrParts + '.methods.';
      deepSet(models, strObject + prop, action, modelName);
      if (createMany) {
        deepSet(models, strObject + 'createMany', action, modelName);
      }
    }
    return models;
  };
  host = app.get('host');
  port = app.get('port');
  servicesJS = {
    models: adapter.allRoutes().reduce(reducer, {}),
    url: 'http://' + host + ':' + port
  };
  configJSON = JSON.stringify(servicesJS, null, '\t');
  return "angular.module('" + (opts.name || (app.get('serverName') + '.services')) + "', [ 'loopback.provider' ])\n\n.config([\"LoopBackResourceProvider\", function(LoopBackResourceProvider) {\n  LoopBackResourceProvider.setConfig(" + configJSON + ");\n}]);";
};
