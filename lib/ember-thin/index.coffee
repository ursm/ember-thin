{get, keys, required} = Ember

Ember.Thin =
  ajax: (url, method, data = {}) ->
    new Ember.RSVP.Promise (resolve, reject) ->
      data = JSON.stringify(data) unless method == 'GET'

      Ember.$.ajax(
        url:         url
        type:        method
        data:        data
        dataType:    'json'
        contentType: 'application/json; charset=utf-8'
      ).then(resolve, reject)

Ember.Thin.config = config =
  rootUrl: ''

Ember.Thin.Model = Ember.Object.extend
  toJSON: ->
    @getProperties keys(@constructor.schema.fields)

  _url: Ember.computed(->
    baseUrl = config.rootUrl + @constructor.schema._url

    Ember.A([baseUrl, @get('id')]).compact().join('/')
  ).property('id')

Ember.Thin.Model.reopenClass
  define: (block) ->
    schema = Ember.Thin.Schema.create()

    block.call schema

    klass = @extend()
    klass.schema = schema

    do klass._setupRelations

    klass

  _setupRelations: ->
    definition = {}

    for name, options of @schema.relations
      definition[name] = @_getHasMany(name, options)

    @reopen definition

  _getHasMany: (key, options) ->
    Ember.computed(->
      type = get(Ember.lookup, options.type) if typeof(options.type) == 'string'

      Ember.Thin.HasManyArray.create(
        key:     key
        type:    type
        parent:  this
        options: options
      )
    ).property()

Ember.Thin.Schema = Ember.Object.extend
  _url:      null
  fields:    {}
  relations: {}

  url: (@_url) ->

  field: (name, options = {}) ->
    @fields[name] = options

  hasMany: (name, options = {}) ->
    @relations[name] = options

Ember.Thin.HasManyArray = Ember.ArrayProxy.extend
  key:      required()
  type:     required()
  parent:   required()
  isLoaded: false

  fetch: ->
    Ember.Thin.ajax(@get('_url'), 'GET').then (json) =>
      @setProperties
        content:  Ember.A(json[@get('key')])
        isLoaded: true

      this

  _url: Ember.computed(->
    if @options.nested
      @get('parent._url') + @get('type.schema._url')
    else
      config.rootUrl + @get('type.schema._url')
  ).property()
