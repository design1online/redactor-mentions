# grab global object
root = exports ? this

# grab redactor globals
$ = root.jQuery
utils = root.RedactorUtils = root.RedactorUtils ? {}
plugins = root.RedactorPlugins = root.RedactorPlugins ? {}

$.extend utils, do ->
    getCursorInfo: ->
        selection: window.getSelection()
        range: selection.getRangeAt 0
        offset: range.startOffset
        container: range.startContainer

    any: (arr) ->
        for element in arr
            return true if element
        false

$.extend plugins, do ->
    update_select = ->
        if this.cursorInMention()
            this.filterUsers()
            this.$userSelect.show()
        else
            this.$userSelect.hide()

    mentions:
        # setup
        init: ->
            this.users = null         # array of user information
            this.select_state = null  # state of display of user select
            this.selected = null      # current user select index
            this.$userSelect = null   # user select element

            this.validateOptions()

            this.loadUsers()
            this.setupUserSelect()
            this.$editor.keydown $.proxy(this.editorKeydown, this)
            this.$editor.mousedown $.proxy(this.editorMousedown, this)

        validateOptions: ->
            required = [
                "usersUrl"
                "maxUsers"
            ]
            for name in required
                if not this.opts[name]
                    throw "Mention plugin requires option: #{ name }"

        loadUsers: ->
            that = this

            $.getJSON this.opts.usersUrl, (data) ->
                that.users = data
                for user, i in that.users
                    user.$element = $ '''
                        <li class="user">
                            <img src="#{ user.icon }" />#{ user.username }  (#{ user.name })
                        </li>'''
                    user.$element.data 'username', user.username
                    user.$element.data 'index', i

        setupUserSelect: ->
            this.select_state = false
            this.$userSelect = $ '<ol class="redactor_ user_select"></ol>'
            this.$userSelect.mousemove $.proxy(this.selectMousemove, this)
            this.$userSelect.mousedown $.proxy(this.selectMousedown, this)
            this.$userSelect.hide()
            this.$editor.after this.$userSelect

        # select event handlers
        selectMousemove: (e) ->
            $target = $ e.target
            if $target.hasClass 'user'
                this.selected = this.$userSelect.children().index $target
                this.paintSelected()

        selectMousedown: (e) ->
            if this.select_state
                e.preventDefault()
                this.chooseUser()
                this.closeMention()
                this.setCursorAfterMention()
                this.disableSelect()

        # editor event handlers
        editorKeydown: (e) ->
            that = this

            if this.cursorInMention()
                switch e.keyCode
                    when 27, 32  # escape, space
                        this.closeMention()
                        this.disableSelect()

                    when 9, 13  # tab, return
                        e.preventDefault()

                        # work around to prevent tabs being inser
                        tabFocus = this.opts.tabFocus
                        this.opts.tabFocus = false

                        this.chooseUser()
                        this.closeMention()
                        this.setCursorAfterMention()
                        this.disableSelect()

                        # reset tabFocus when you return to the event loop
                        setTimeout ->
                            that.opts.tabFocus = tabFocus
                        , 0

                    when 38  # up
                        e.preventDefault()
                        this.moveSelectUp()

                    when 40  # down
                        e.preventDefault()
                        this.moveSelectDown()

            else if this.cursorAfterMentionStart()
                this.createMention()
                this.enableSelect()

            # after every key press, make sure that select state is correct
            setTimeout $.proxy(update_select, this), 0

        editorMousedown: ->
            # after every mousepress, make sure that select state is correct
            setTimeout $.proxy(update_select, this), 0

        # select navigation
        moveSelectUp: ->
            if this.selected > 0
                this.selected -= 1
            this.paintSelected()

        moveSelectDown: ->
            if this.selected < this.$userSelect.children().length - 1
                this.selected += 1
            this.paintSelected()

        # select state
        enableSelect: ->
            this.select_state = true
            this.selected = 0

            # build initial user select
            for i in [0...this.opts.maxUsers]
                this.$userSelect.append this.users[i].$element

            this.paintSelected()
            this.$userSelect.show()

        disableSelect: ->
            this.select_state = false
            this.selected = null
            this.$userSelect.children().detach()
            this.$userSelect.hide()

        # select display
        paintSelected: ->
            $elements = $ 'li', this.$userSelect
            $elements.removeClass 'selected'
            $elements.eq(this.selected).addClass 'selected'

        # select utils
        chooseUser: ->
            i = this.$userSelect.children('li').eq(this.selected).data 'index'
            user = this.users[i]
            mention = this.getCurrentMention()
            mention.attr "href", "/user/{# user.username }"
            mention.text "@{# user.username }"

        filterUsers: ->
            # empty out userSelect
            this.$userSelect.children().detach()

            # query for filter_string once
            filter_string = this.getFilterString()

            # build filtered users list
            count = 0
            for user in this.users
                # break on max filter users
                break if count >= this.opts.maxUsers

                if this.filterTest user, filter_string
                    this.$userSelect.append user.$element
                    count++

            this.paintSelected()

        filterTest: (user, filter_string) ->
            filter_string = filter_string.toLowerCase()
            test_strings = [
                user.username.toLowerCase()
                user.name.toLowerCase()
            ]
            utils.any(test_strings.map((el) ->
                el.indexOf(filter_string) != -1
            ))

        getFilterString: ->
            mention = this.getCurrentMention()
            filter_str = mention.text()
            # remove @ from the begining
            filter_str = filter_str.slice 1
            # remove zero width spaces
            filter_str.replace '\u200b', ''

        # mention
        createMention: ->
            cursor_info = utils.getCursorInfo()
            mention = $ '<a href="#" class="mention">@\u200b</a>'

            # make sure mention links aren't clickable
            mention.click (e) ->
                e.preventDefault()

            # insert mention where cursor is at
            # figure out what text is left and right of the cursor
            left = cursor_info.container.data.slice 0, cursor_info.offset
            right = cursor_info.container.data.slice cursor_info.offset

            # slice off the @ sign
            left = left.slice 0, -1

            # insert the mention inbetween left and right
            cursor_info.container.data = left
            mention.insertAfter cursor_info.container
            mention.after right

            # set cursor positon into mention
            new_range = document.createRange()
            new_range.setStart mention[0].firstChild, 1
            new_range.setEnd mention[0].firstChild, 1
            cursor_info.selection.removeAllRanges()
            cursor_info.selection.addRange new_range

        closeMention: ->
            mention = this.getCurrentMention()
            mention.attr "contenteditable", "false"

        # helpers
        getCurrentMention: ->
            # return the current mention based on cursor position, if there
            # isn't one then return false

            # first check the current element, if it is a mention return it
            current = $ this.getCurrent()
            return current if current.hasClass 'mention'

            # else select from parents
            parents = current.parents '.mention'
            return parents.eq 0 if parents.length > 0

            # default to false
            false

        cursorInMention: ->
            this.getCurrentMention().length > 0

        cursorAfterMentionStart: ->
            matches = [
                "@"
                " @"
                "\u200b@"
                "@\u200B"
            ]

            # get cursor element and offset
            cursor_info = utils.getCursorInfo()

            # if cursor isn't on a text element return false
            return false if cursor_info.container.nodeName != "#text"

            # figure out what is left of the cursor
            left = cursor_info.container.data.slice 0, cursor_info.offset
            previous_chars = left.slice -2

            utils.any(matches.map((el) ->
                el == previous_chars
            ))

        setCursorAfterMention: ->
            mention = this.getCurrentMention()

            # insert space after mention
            mention.after " "

            # set cursor
            selection = window.getSelection()
            new_range = document.createRange()
            new_range.setStart mention[0].nextSibling, 1
            new_range.setEnd mention[0].nextSibling, 1
            selection.removeAllRanges()
            selection.addRange new_range