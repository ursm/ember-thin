assert = require('assert')
sinon  = require('sinon')

global.ENV =
  EXTEND_PROTOTYPES: false

require './vendor/ember-runtime'
require '../lib/ember-thin'

beforeEach ->
  @sinon = sinon.sandbox.create()

  @stubAjax = (method, url, returns) =>
    promise = new Ember.RSVP.Promise (resolve, reject) ->
      resolve returns

    @sinon.stub(Ember.Thin, 'ajax').withArgs(method, url).returns promise

afterEach ->
  do @sinon.restore

beforeEach ->
  Ember.Thin.ajax = -> throw new Error('must stub it')

  Ember.Thin.config.rootUrl = '/api'

  global.App = Ember.Application.create()

  App.Organization = Ember.Thin.Schema.define ->
    @url '/organizations'

    @field 'id'
    @field 'name'

    @hasMany 'members', type: 'App.User', inverse: 'organization', nested: true

  App.User = Ember.Thin.Schema.define ->
    @url '/users'

    @field 'id'
    @field 'name'
    @field 'realName'

    @belongsTo 'organization', type: 'App.Organization', inverse: 'members'
    @hasMany   'rooms',        type: 'App.Room',         inverse: 'members', nested: true

  App.Room = Ember.Thin.Schema.define ->
    @url '/rooms'

    @field 'id'
    @field 'name'

    @hasMany 'members', type: 'App.User', inverse: 'rooms', nested: true

describe 'Ember.Thin', ->
  describe '.load', ->
    it 'should load payload and return a model', ->
      user = App.User.load(id: 42, real_name: 'foo')

      assert.equal user.get('id'),       42
      assert.equal user.get('realName'), 'foo'

    it 'should load hasMany relation within payload', ->
      user = App.User.load(id: 42, rooms: [
        {id: 1, name: 'foo'}
        {id: 2, name: 'bar'}
      ])

      assert.ok    user.get('rooms.isLoaded')
      assert.equal user.get('rooms.length'),           2
      assert.equal user.get('rooms.firstObject.name'), 'foo'

    it 'should load belongsTo relation within payload', ->
      user = App.User.load(id: 42, organization: {id: 4423, name: 'esminc'})

      assert.equal user.get('organizationId'),           4423
      assert.equal user.get('organization').constructor, App.Organization
      assert.equal user.get('organization.name'),        'esminc'

    context 'twice', ->
      it 'should update a record', ->
        one = App.User.load(id: 42, name: 'foo')
        two = App.User.load(id: 42, name: 'bar')

        assert.equal one, two
        assert.equal two.get('name'), 'bar'

  describe '.toJSON', ->
    it 'should convert to an object', ->
      json = App.User.create(id: 42, name: 'ursm', realName: 'Keita Urashima').toJSON()

      assert.equal json.id,        42
      assert.equal json.name,      'ursm'
      assert.equal json.real_name, 'Keita Urashima'

  describe '.save', ->
    beforeEach ->
      @user = App.User.create()

    context 'when record is unsaved', ->
      beforeEach ->
        @stubAjax 'POST', '/api/users', id: 42

      it 'should post data', (done) ->
        @user.save().then (user) =>
          assert.equal user, @user
          assert.equal user.get('id'), 42
          do done

    context 'when record is saved', ->
      beforeEach ->
        @user.set 'id', 42

        @stubAjax 'PUT', '/api/users/42', id: 42, name: 'ursm'

      it 'should post data', (done) ->
        @user.save().then (user) =>
          assert.equal user, @user
          assert.equal user.get('name'), 'ursm'
          do done

  describe 'one-to-many relation', ->
    describe '.load', ->
      it 'should load records', ->
        org     = App.Organization.load(id: 42)
        members = org.get('members')

        assert.ok    !members.get('isLoaded')
        assert.equal members.get('length'), 0

        members.load [
          {id: 1}
          {id: 2}
        ]

        assert.ok    members.get('isLoaded')
        assert.equal members.get('length'), 2
        assert.equal members.get('firstObject').constructor, App.User

      it 'should get parent model', ->
        org     = App.Organization.load(id: 42)
        members = org.get('members')

        assert.equal members.get('parent'), org

    context 'get unloaded relation', ->
      beforeEach ->
        @stubAjax 'GET', '/api/organizations/42/members', [
          {id: 1}
          {id: 2}
          {id: 3}
        ]

      it 'should fetch records', (done) ->
        org = App.Organization.load(id: 42)

        org.get('members').on 'load', (members) ->
          assert.ok    members.get('isLoaded')
          assert.equal members.get('length'), 3
          do done

        # trigger 'load'
        org.get('members.firstObject')

  describe 'belongsTo relation', ->
    it 'should moved on with foreign key', ->
      org1 = App.Organization.load(id: 42)
      org2 = App.Organization.load(id: 4423)

      user = App.User.load(id: 1, organization_id: 42)

      assert.equal user.get('organization'), org1

      user.set 'organizationId', 4423

      assert.equal user.get('organization'), org2

    context 'when inverse relation is loaded', ->
      beforeEach ->

      it 'should be automatically wired', ->
        org = App.Organization.load(id: 42)
        org.get('members').load()

        user = App.User.load(id: 1, organization_id: 42)

        assert.equal user.get('organization'), org
        assert.ok    org.get('members').contains(user)

    context 'when inverse relation is not loaded', ->
      it 'should not do anything', ->
        org  = App.Organization.load(id: 42)
        user = App.User.load(id: 1, organization_id: 42)

        assert.equal user.get('organization'), org
        assert.ok    !org.get('members.isLoaded')
