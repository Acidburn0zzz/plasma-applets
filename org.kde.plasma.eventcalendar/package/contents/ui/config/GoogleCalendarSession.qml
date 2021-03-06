import QtQuick 2.0

import ".."
import "../utils.js" as Utils

Item {
    id: session

    Logger {
        id: logger
        showDebug: plasmoid.configuration.debugging
    }

    // Client
    property string clientId: plasmoid.configuration.client_id
    property string clientSecret: plasmoid.configuration.client_secret

    // New Session
    property string deviceCode: ''
    property string userCode: ''
    property int userCodeExpiresAt: 0
    property int userCodePollInterval: 0

    // Active Session
    property string accessToken: plasmoid.configuration.access_token
    property string accessTokenType: plasmoid.configuration.access_token_type
    property int accessTokenExpiresAt: plasmoid.configuration.access_token_expires_at
    property string refreshToken: plasmoid.configuration.refresh_token

    // Data
    property var calendarListData: ConfigSerializedString {
        id: calendarListData
        configKey: 'calendar_list'
        defaultValue: []
    }
    property alias calendarList: calendarListData.value

    property var calendarIdListData: ConfigSerializedString {
        id: calendarIdListData
        configKey: 'calendar_id_list'
        defaultValue: []

        function serialize() {
            plasmoid.configuration[configKey] = value.join(',')
        }
        function deserialize() {
            value = configValue.split(',')
        }
    }
    property alias calendarIdList: calendarIdListData.value

    signal newAccessToken()


    //---
    function getUserCode(callback) {
        var url = 'https://accounts.google.com/o/oauth2/device/code';
        Utils.post({
            url: url,
            data: {
                client_id: clientId,
                scope: 'https://www.googleapis.com/auth/calendar',
            },
        }, callback);
    }

    function generateUserCodeAndPoll() {
        getUserCode(function(err, data) {
            data = JSON.parse(data)
            logger.debug('/o/oauth2/device/code Response', JSON.stringify(data, null, '\t'))

            deviceCode = data.device_code
            userCode = data.user_code
            //... = data.verification_url // == "https://www.google.com/device"
            userCodeExpiresAt = Date.now() + data.expires_in * 1000
            userCodePollInterval = data.interval

            userCodePollTimer.interval = data.interval * 1000
            userCodePollTimer.start()
        });
    }

    Timer {
        id: userCodePollTimer
        interval: 5000
        running: false
        repeat: true
        onTriggered: pollAccessToken()
    }

    function pollAccessToken() {
        var url = 'https://www.googleapis.com/oauth2/v4/token';
        Utils.post({
            url: url,
            data: {
                client_id: clientId,
                client_secret: clientSecret,
                code: deviceCode,
                grant_type: 'http://oauth.net/grant_type/device/1.0',
            },
        }, function(err, data) {
            data = JSON.parse(data)
            logger.debug('/oauth2/v4/token Response', JSON.stringify(data, null, '\t'))

            if (data.error) {
                // Not yet ready
                return
            }

            // Ready
            userCodePollTimer.stop()
            updateAccessToken(data)
        });
    }

    function updateAccessToken(data) {
        plasmoid.configuration.access_token = data.access_token
        plasmoid.configuration.access_token_type = data.token_type
        plasmoid.configuration.access_token_expires_at = Date.now() + data.expires_in * 1000
        plasmoid.configuration.refresh_token = data.refresh_token
        newAccessToken()
    }

    onNewAccessToken: updateCalendarList()

    function updateCalendarList() {
        logger.debug('updateCalendarList')
        logger.debug('access_token', accessToken)
        fetchGCalCalendars({
            access_token: accessToken,
        }, function(err, data, xhr) {
            calendarListData.value = data.items
        });
    }

    function fetchGCalCalendars(args, callback) {
        var url = 'https://www.googleapis.com/calendar/v3/users/me/calendarList';
        Utils.getJSON({
            url: url,
            headers: {
                "Authorization": "Bearer " + args.access_token,
            }
        }, function(err, data, xhr) {
            // console.log('fetchGCalCalendars.response', err, data, xhr.status);
            if (!err && data && data.error) {
                return callback(data, null, xhr);
            }
            callback(err, data, xhr);
        });
    }

    function reset() {
        accessToken = ''
        refreshToken = ''
        calendarList = []
        calendarIdList = []
        generateUserCodeAndPoll()
    }
}
