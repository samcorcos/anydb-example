if Meteor.isServer
  # Connect to Neo4j
  @Neo4j = Neo4j = new Neo4jDB("http://neo4j_test:QjCTKSXHFKMezZc40Say@neo4jtest.sb05.stations.graphenedb.com:24789")

  DB.publish
    name: 'chatrooms'

    # Creates the query for all chatrooms
    query: ->
      Neo4j.query """
        MATCH (room:ROOM)
        RETURN room
        ORDER BY room.createdAt DESC
      """

    # Sets any dependencies for the chatroom subscription
    depends: -> ['chatrooms']

  DB.publish
    name: 'msgs'

    # Creates the query for all messages within the current chatroom
    query: (roomId) ->
      Neo4j.query """
        MATCH (room:ROOM {_id:"#{roomId}"})-->(msg:MSG)
        RETURN msg
        ORDER BY msg.createdAt DESC
      """

    # Sets a dependency only on the chatroom with the current roomId
    depends: (roomId) -> ["chatroom:#{roomId}"]

if Meteor.isClient
  Session.setDefault 'roomId', null
  Session.setDefault 'msgs', []

  # Creates a subscription object that will contain
  # the subscription for both rooms and messages
  @subs = {}
  subs.rooms = DB.createSubscription('chatrooms')

  Template.main.onRendered ->
    # When the template is rendered, start the rooms subscription
    @autorun -> subs.rooms.start()
    # Watch for the roomId to change
    @autorun ->
      roomId = Session.get('roomId')
      if roomId
        # Start a subscription for the msgs of that room
        subs.msgs = DB.createSubscription('msgs', roomId)
        subs.msgs.start()
        # Watch for changes to the messages
        Tracker.autorun ->
          Session.set('msgs', subs.msgs.fetch())

  Template.main.helpers
    rooms: -> subs.rooms
    msgs: -> Session.get 'msgs'
    isCurrentRoom: (roomId) -> Session.equals('roomId', roomId)
    currentRoom: (roomId) -> Session.get('roomId')

  newMsg = (text) ->
    id = DB.newId()
    Meteor.call 'newMsg', Session.get('roomId'), id, text, (err,res) ->
      if err then subs.msgs.handleUndo(id)

  newRoom = () ->
    id = Random.hexString(24)
    Meteor.call 'newRoom', id, (err,res) ->
      if err then subs.rooms.handleUndo(id)
    Session.set('roomId', id)


  Template.main.events
    # When you click on a room within the rooms list,
    # you set the current room to the one you selected.
    'click .room': ->
      Session.set('roomId', @_id)
    # Creates a new room
    'click .newRoom': (e,t) ->
      newRoom()
    # Creates a new message
    'click .newMsg': (e,t) ->
      input = t.find('input').value
      newMsg(input)
      t.find('input').value = ''
    'keyup #input': (e,t) ->
      if e.keyCode is 13
        input = t.find('input').value
        newMsg(input)
        t.find('input').value = ''
    'click #reset': (e,t) ->
      Meteor.call "neo4jreset"


Meteor.methods
  neo4jreset: ->
    if Meteor.isServer
      Neo4j.reset()
    else
      window.location.reload()

  newRoom: (id) ->
    check(id, String)
    room =
      _id: id
      createdAt: Date.now()
    if Meteor.isServer
      # Creates a new room
      Neo4j.query "CREATE (:ROOM #{Neo4j.stringify(room)})"
      # Triggers re-query for all chatrooms dependencies
      DB.triggerDeps('chatrooms')
    else
      # Much of what you see below is for latency compensation
      fields = R.pipe(
        R.assoc('unverified', true),
        R.omit(['_id'])
      )(room)
      subs.rooms.addedBefore(id, fields, subs.rooms.docs[0]?._id or null)
      subs.rooms.addUndo id, -> subs.rooms.removed(id)
      Session.set('roomId', id)

  newMsg: (roomId, id, text) ->
    check(id, String)
    check(text, String)
    msg =
      _id: id
      text: text
      createdAt: Date.now()
    if Meteor.isServer
      Neo4j.query """
        MATCH (room:ROOM {_id:"#{roomId}"})
        CREATE (room)-[:OWNS]->(:MSG #{Neo4j.stringify(msg)})
      """
      DB.triggerDeps("chatroom:#{roomId}")
    else
      fields = R.pipe(
        R.assoc('unverified', true)
        R.omit(['_id'])
      )(msg)
      subs.msgs.addedBefore(id, fields, subs.msgs.docs[0]?._id or null)
      subs.msgs.addUndo id, -> subs.msgs.removed(id)
