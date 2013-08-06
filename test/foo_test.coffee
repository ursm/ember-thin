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

  App.User = Ember.Thin.Schema.define ->
    @url '/users'

    @field 'id'
    @field 'screenName'

    @hasMany 'followings',      type: 'App.User',    inverse: 'followers'
    @hasMany 'followers',       type: 'App.User',    inverse: 'followings'
    @hasMany 'tweets',          type: 'App.Tweet',   inverse: 'user',       nested: true
    @hasMany 'messages',        type: 'App.Message', inverse: 'to',         nested: true
    @hasMany 'sentMessages',    type: 'App.Message', inverse: 'from',       nested: true
    @hasMany 'lists',           type: 'App.List',    inverse: 'owner',      nested: true
    @hasMany 'subscribedLists', type: 'App.List',    inverse: 'subscribers'
    @hasMany 'memberOfLists',   type: 'App.List',    inverse: 'members'

  App.Tweet = Ember.Thin.Schema.define ->
    @url '/tweets'

    @field 'id'
    @field 'body'

    @belongsTo 'user', type: 'App.User', inverse: 'tweets'

  App.Message = Ember.Thin.Schema.define ->
    @url '/messages'

    @field 'id'
    @field 'body'

    @belongsTo 'from', type: 'App.User', inverse: 'sentMessages'
    @belongsTo 'to',   type: 'App.User', inverse: 'messages'

  App.List = Ember.Thin.Schema.define ->
    @url '/lists'

    @field 'id'
    @field 'name'

    @belongsTo 'owner', type: 'App.User'

    @hasMany 'members',     type: 'App.User', inverse: 'memberOfLists'
    @hasMany 'subscribers', type: 'App.User', inverse: 'subscribedLists'

describe 'Ember.Thin', ->
  describe '.load', ->
    it 'should load payload and return a model', ->
      user = App.User.load(id: 42, screen_name: 'ursm')

      assert.equal user.get('id'),         42
      assert.equal user.get('screenName'), 'ursm'

    it 'should load hasMany relation within payload', ->
      user = App.User.load(id: 42, tweets: [
        {id: 1, body: 'hello'}
        {id: 2, body: 'world'}
      ])

      assert.ok    user.get('tweets.isLoaded')
      assert.equal user.get('tweets.length'),           2
      assert.equal user.get('tweets.firstObject.body'), 'hello'

    it 'should load belongsTo relation within payload', ->
      tweet = App.Tweet.load(id: 42, user: {id: 4423, screen_name: 'ursm'})

      assert.equal tweet.get('userId'),           4423
      assert.equal tweet.get('user').constructor, App.User
      assert.equal tweet.get('user.screenName'),  'ursm'

    context 'twice', ->
      it 'should update a record', ->
        one = App.User.load(id: 42, screen_name: 'foo')
        two = App.User.load(id: 42, screen_name: 'bar')

        assert.equal one, two
        assert.equal two.get('screenName'), 'bar'

  describe '.toJSON', ->
    it 'should convert to an object', ->
      json = App.User.create(id: 42, screenName: 'ursm').toJSON()

      assert.deepEqual json, {id: 42, screen_name: 'ursm'}

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

        @stubAjax 'PUT', '/api/users/42', id: 42, screen_name: 'ursm'

      it 'should post data', (done) ->
        @user.save().then (user) =>
          assert.equal user, @user
          assert.equal user.get('screenName'), 'ursm'
          do done

  describe 'one-to-many relation', ->
    it 'should get parent model', ->
      user = App.User.load(id: 42)

      assert.equal user.get('tweets.parent'), user

    describe '.load', ->
      it 'should load records', ->
        user   = App.User.load(id: 42)
        tweets = user.get('tweets')

        assert.ok    !tweets.get('isLoaded')
        assert.equal tweets.get('length'), 0

        tweets.load [
          {id: 1}
          {id: 2}
        ]

        assert.ok    tweets.get('isLoaded')
        assert.equal tweets.get('length'), 2
        assert.equal tweets.get('firstObject').constructor, App.Tweet

    context 'get unloaded relation', ->
      beforeEach ->
        @stubAjax 'GET', '/api/users/42/tweets', [
          {id: 1}
          {id: 2}
          {id: 3}
        ]

      it 'should fetch records', (done) ->
        user = App.User.load(id: 42)

        user.get('tweets').on 'didLoad', (tweets) ->
          assert.ok    tweets.get('isLoaded')
          assert.equal tweets.get('length'),                  3
          assert.equal tweets.get('firstObject').constructor, App.Tweet
          do done

        # trigger 'didLoad'
        user.get('tweets.firstObject')

  describe 'belongsTo relation', ->
    it 'should moved on with foreign key', ->
      user1 = App.User.load(id: 42)
      user2 = App.User.load(id: 4423)

      list = App.List.load(id: 1, owner_id: 42)

      assert.equal list.get('owner'), user1

      list.set 'ownerId', 4423

      assert.equal list.get('owner'), user2

    context 'when inverse relation is loaded', ->
      it 'should be automatically wired', ->
        user = App.User.load(id: 42)
        user.get('tweets').load()

        tweet = App.Tweet.load(id: 1, user_id: 42)

        assert.equal tweet.get('user'), user
        assert.ok    user.get('tweets').contains(tweet)

    context 'when inverse relation is not loaded', ->
      it 'should not do anything', ->
        user  = App.User.load(id: 42)
        tweet = App.Tweet.load(id: 1, user_id: 42)

        assert.equal tweet.get('user'), user
        assert.ok    !user.get('tweets.isLoaded')
