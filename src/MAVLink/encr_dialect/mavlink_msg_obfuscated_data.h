#pragma once
// MESSAGE OBFUSCATED_DATA PACKING

#define MAVLINK_MSG_ID_OBFUSCATED_DATA 11001


typedef struct __mavlink_obfuscated_data_t {
 uint8_t target_id; /*<  System ID*/
 uint8_t len; /*<  Message Length*/
 uint8_t nonce[24]; /*<  Counter to prevent the same key being used to hash any message*/
 uint8_t tag[16]; /*<  Auth tag for ChaCha20*/
 uint8_t data[200]; /*<  Encrypted Payload*/
} mavlink_obfuscated_data_t;

#define MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN 242
#define MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN 242
#define MAVLINK_MSG_ID_11001_LEN 242
#define MAVLINK_MSG_ID_11001_MIN_LEN 242

#define MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC 61
#define MAVLINK_MSG_ID_11001_CRC 61

#define MAVLINK_MSG_OBFUSCATED_DATA_FIELD_NONCE_LEN 24
#define MAVLINK_MSG_OBFUSCATED_DATA_FIELD_TAG_LEN 16
#define MAVLINK_MSG_OBFUSCATED_DATA_FIELD_DATA_LEN 200

#if MAVLINK_COMMAND_24BIT
#define MAVLINK_MESSAGE_INFO_OBFUSCATED_DATA { \
    11001, \
    "OBFUSCATED_DATA", \
    5, \
    {  { "target_id", NULL, MAVLINK_TYPE_UINT8_T, 0, 0, offsetof(mavlink_obfuscated_data_t, target_id) }, \
         { "len", NULL, MAVLINK_TYPE_UINT8_T, 0, 1, offsetof(mavlink_obfuscated_data_t, len) }, \
         { "nonce", NULL, MAVLINK_TYPE_UINT8_T, 24, 2, offsetof(mavlink_obfuscated_data_t, nonce) }, \
         { "tag", NULL, MAVLINK_TYPE_UINT8_T, 16, 26, offsetof(mavlink_obfuscated_data_t, tag) }, \
         { "data", NULL, MAVLINK_TYPE_UINT8_T, 200, 42, offsetof(mavlink_obfuscated_data_t, data) }, \
         } \
}
#else
#define MAVLINK_MESSAGE_INFO_OBFUSCATED_DATA { \
    "OBFUSCATED_DATA", \
    5, \
    {  { "target_id", NULL, MAVLINK_TYPE_UINT8_T, 0, 0, offsetof(mavlink_obfuscated_data_t, target_id) }, \
         { "len", NULL, MAVLINK_TYPE_UINT8_T, 0, 1, offsetof(mavlink_obfuscated_data_t, len) }, \
         { "nonce", NULL, MAVLINK_TYPE_UINT8_T, 24, 2, offsetof(mavlink_obfuscated_data_t, nonce) }, \
         { "tag", NULL, MAVLINK_TYPE_UINT8_T, 16, 26, offsetof(mavlink_obfuscated_data_t, tag) }, \
         { "data", NULL, MAVLINK_TYPE_UINT8_T, 200, 42, offsetof(mavlink_obfuscated_data_t, data) }, \
         } \
}
#endif

/**
 * @brief Pack a obfuscated_data message
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param msg The MAVLink message to compress the data into
 *
 * @param target_id  System ID
 * @param len  Message Length
 * @param nonce  Counter to prevent the same key being used to hash any message
 * @param tag  Auth tag for ChaCha20
 * @param data  Encrypted Payload
 * @return length of the message in bytes (excluding serial stream start sign)
 */
static inline uint16_t mavlink_msg_obfuscated_data_pack(uint8_t system_id, uint8_t component_id, mavlink_message_t* msg,
                               uint8_t target_id, uint8_t len, const uint8_t *nonce, const uint8_t *tag, const uint8_t *data)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN];
    _mav_put_uint8_t(buf, 0, target_id);
    _mav_put_uint8_t(buf, 1, len);
    _mav_put_uint8_t_array(buf, 2, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, tag, 16);
    _mav_put_uint8_t_array(buf, 42, data, 200);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), buf, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
#else
    mavlink_obfuscated_data_t packet;
    packet.target_id = target_id;
    packet.len = len;
    mav_array_assign_uint8_t(packet.nonce, nonce, 24);
    mav_array_assign_uint8_t(packet.tag, tag, 16);
    mav_array_assign_uint8_t(packet.data, data, 200);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), &packet, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
#endif

    msg->msgid = MAVLINK_MSG_ID_OBFUSCATED_DATA;
    return mavlink_finalize_message(msg, system_id, component_id, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
}

/**
 * @brief Pack a obfuscated_data message
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param status MAVLink status structure
 * @param msg The MAVLink message to compress the data into
 *
 * @param target_id  System ID
 * @param len  Message Length
 * @param nonce  Counter to prevent the same key being used to hash any message
 * @param tag  Auth tag for ChaCha20
 * @param data  Encrypted Payload
 * @return length of the message in bytes (excluding serial stream start sign)
 */
static inline uint16_t mavlink_msg_obfuscated_data_pack_status(uint8_t system_id, uint8_t component_id, mavlink_status_t *_status, mavlink_message_t* msg,
                               uint8_t target_id, uint8_t len, const uint8_t *nonce, const uint8_t *tag, const uint8_t *data)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN];
    _mav_put_uint8_t(buf, 0, target_id);
    _mav_put_uint8_t(buf, 1, len);
    _mav_put_uint8_t_array(buf, 2, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, tag, 16);
    _mav_put_uint8_t_array(buf, 42, data, 200);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), buf, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
#else
    mavlink_obfuscated_data_t packet;
    packet.target_id = target_id;
    packet.len = len;
    mav_array_memcpy(packet.nonce, nonce, sizeof(uint8_t)*24);
    mav_array_memcpy(packet.tag, tag, sizeof(uint8_t)*16);
    mav_array_memcpy(packet.data, data, sizeof(uint8_t)*200);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), &packet, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
#endif

    msg->msgid = MAVLINK_MSG_ID_OBFUSCATED_DATA;
#if MAVLINK_CRC_EXTRA
    return mavlink_finalize_message_buffer(msg, system_id, component_id, _status, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
#else
    return mavlink_finalize_message_buffer(msg, system_id, component_id, _status, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
#endif
}

/**
 * @brief Pack a obfuscated_data message on a channel
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param chan The MAVLink channel this message will be sent over
 * @param msg The MAVLink message to compress the data into
 * @param target_id  System ID
 * @param len  Message Length
 * @param nonce  Counter to prevent the same key being used to hash any message
 * @param tag  Auth tag for ChaCha20
 * @param data  Encrypted Payload
 * @return length of the message in bytes (excluding serial stream start sign)
 */
static inline uint16_t mavlink_msg_obfuscated_data_pack_chan(uint8_t system_id, uint8_t component_id, uint8_t chan,
                               mavlink_message_t* msg,
                                   uint8_t target_id,uint8_t len,const uint8_t *nonce,const uint8_t *tag,const uint8_t *data)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN];
    _mav_put_uint8_t(buf, 0, target_id);
    _mav_put_uint8_t(buf, 1, len);
    _mav_put_uint8_t_array(buf, 2, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, tag, 16);
    _mav_put_uint8_t_array(buf, 42, data, 200);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), buf, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
#else
    mavlink_obfuscated_data_t packet;
    packet.target_id = target_id;
    packet.len = len;
    mav_array_assign_uint8_t(packet.nonce, nonce, 24);
    mav_array_assign_uint8_t(packet.tag, tag, 16);
    mav_array_assign_uint8_t(packet.data, data, 200);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), &packet, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
#endif

    msg->msgid = MAVLINK_MSG_ID_OBFUSCATED_DATA;
    return mavlink_finalize_message_chan(msg, system_id, component_id, chan, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
}

/**
 * @brief Encode a obfuscated_data struct
 *
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param msg The MAVLink message to compress the data into
 * @param obfuscated_data C-struct to read the message contents from
 */
static inline uint16_t mavlink_msg_obfuscated_data_encode(uint8_t system_id, uint8_t component_id, mavlink_message_t* msg, const mavlink_obfuscated_data_t* obfuscated_data)
{
    return mavlink_msg_obfuscated_data_pack(system_id, component_id, msg, obfuscated_data->target_id, obfuscated_data->len, obfuscated_data->nonce, obfuscated_data->tag, obfuscated_data->data);
}

/**
 * @brief Encode a obfuscated_data struct on a channel
 *
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param chan The MAVLink channel this message will be sent over
 * @param msg The MAVLink message to compress the data into
 * @param obfuscated_data C-struct to read the message contents from
 */
static inline uint16_t mavlink_msg_obfuscated_data_encode_chan(uint8_t system_id, uint8_t component_id, uint8_t chan, mavlink_message_t* msg, const mavlink_obfuscated_data_t* obfuscated_data)
{
    return mavlink_msg_obfuscated_data_pack_chan(system_id, component_id, chan, msg, obfuscated_data->target_id, obfuscated_data->len, obfuscated_data->nonce, obfuscated_data->tag, obfuscated_data->data);
}

/**
 * @brief Encode a obfuscated_data struct with provided status structure
 *
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param status MAVLink status structure
 * @param msg The MAVLink message to compress the data into
 * @param obfuscated_data C-struct to read the message contents from
 */
static inline uint16_t mavlink_msg_obfuscated_data_encode_status(uint8_t system_id, uint8_t component_id, mavlink_status_t* _status, mavlink_message_t* msg, const mavlink_obfuscated_data_t* obfuscated_data)
{
    return mavlink_msg_obfuscated_data_pack_status(system_id, component_id, _status, msg,  obfuscated_data->target_id, obfuscated_data->len, obfuscated_data->nonce, obfuscated_data->tag, obfuscated_data->data);
}

/**
 * @brief Send a obfuscated_data message
 * @param chan MAVLink channel to send the message
 *
 * @param target_id  System ID
 * @param len  Message Length
 * @param nonce  Counter to prevent the same key being used to hash any message
 * @param tag  Auth tag for ChaCha20
 * @param data  Encrypted Payload
 */
#ifdef MAVLINK_USE_CONVENIENCE_FUNCTIONS

static inline void mavlink_msg_obfuscated_data_send(mavlink_channel_t chan, uint8_t target_id, uint8_t len, const uint8_t *nonce, const uint8_t *tag, const uint8_t *data)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN];
    _mav_put_uint8_t(buf, 0, target_id);
    _mav_put_uint8_t(buf, 1, len);
    _mav_put_uint8_t_array(buf, 2, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, tag, 16);
    _mav_put_uint8_t_array(buf, 42, data, 200);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_OBFUSCATED_DATA, buf, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
#else
    mavlink_obfuscated_data_t packet;
    packet.target_id = target_id;
    packet.len = len;
    mav_array_assign_uint8_t(packet.nonce, nonce, 24);
    mav_array_assign_uint8_t(packet.tag, tag, 16);
    mav_array_assign_uint8_t(packet.data, data, 200);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_OBFUSCATED_DATA, (const char *)&packet, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
#endif
}

/**
 * @brief Send a obfuscated_data message
 * @param chan MAVLink channel to send the message
 * @param struct The MAVLink struct to serialize
 */
static inline void mavlink_msg_obfuscated_data_send_struct(mavlink_channel_t chan, const mavlink_obfuscated_data_t* obfuscated_data)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    mavlink_msg_obfuscated_data_send(chan, obfuscated_data->target_id, obfuscated_data->len, obfuscated_data->nonce, obfuscated_data->tag, obfuscated_data->data);
#else
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_OBFUSCATED_DATA, (const char *)obfuscated_data, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
#endif
}

#if MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN <= MAVLINK_MAX_PAYLOAD_LEN
/*
  This variant of _send() can be used to save stack space by reusing
  memory from the receive buffer.  The caller provides a
  mavlink_message_t which is the size of a full mavlink message. This
  is usually the receive buffer for the channel, and allows a reply to an
  incoming message with minimum stack space usage.
 */
static inline void mavlink_msg_obfuscated_data_send_buf(mavlink_message_t *msgbuf, mavlink_channel_t chan,  uint8_t target_id, uint8_t len, const uint8_t *nonce, const uint8_t *tag, const uint8_t *data)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char *buf = (char *)msgbuf;
    _mav_put_uint8_t(buf, 0, target_id);
    _mav_put_uint8_t(buf, 1, len);
    _mav_put_uint8_t_array(buf, 2, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, tag, 16);
    _mav_put_uint8_t_array(buf, 42, data, 200);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_OBFUSCATED_DATA, buf, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
#else
    mavlink_obfuscated_data_t *packet = (mavlink_obfuscated_data_t *)msgbuf;
    packet->target_id = target_id;
    packet->len = len;
    mav_array_assign_uint8_t(packet->nonce, nonce, 24);
    mav_array_assign_uint8_t(packet->tag, tag, 16);
    mav_array_assign_uint8_t(packet->data, data, 200);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_OBFUSCATED_DATA, (const char *)packet, MAVLINK_MSG_ID_OBFUSCATED_DATA_MIN_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN, MAVLINK_MSG_ID_OBFUSCATED_DATA_CRC);
#endif
}
#endif

#endif

// MESSAGE OBFUSCATED_DATA UNPACKING


/**
 * @brief Get field target_id from obfuscated_data message
 *
 * @return  System ID
 */
static inline uint8_t mavlink_msg_obfuscated_data_get_target_id(const mavlink_message_t* msg)
{
    return _MAV_RETURN_uint8_t(msg,  0);
}

/**
 * @brief Get field len from obfuscated_data message
 *
 * @return  Message Length
 */
static inline uint8_t mavlink_msg_obfuscated_data_get_len(const mavlink_message_t* msg)
{
    return _MAV_RETURN_uint8_t(msg,  1);
}

/**
 * @brief Get field nonce from obfuscated_data message
 *
 * @return  Counter to prevent the same key being used to hash any message
 */
static inline uint16_t mavlink_msg_obfuscated_data_get_nonce(const mavlink_message_t* msg, uint8_t *nonce)
{
    return _MAV_RETURN_uint8_t_array(msg, nonce, 24,  2);
}

/**
 * @brief Get field tag from obfuscated_data message
 *
 * @return  Auth tag for ChaCha20
 */
static inline uint16_t mavlink_msg_obfuscated_data_get_tag(const mavlink_message_t* msg, uint8_t *tag)
{
    return _MAV_RETURN_uint8_t_array(msg, tag, 16,  26);
}

/**
 * @brief Get field data from obfuscated_data message
 *
 * @return  Encrypted Payload
 */
static inline uint16_t mavlink_msg_obfuscated_data_get_data(const mavlink_message_t* msg, uint8_t *data)
{
    return _MAV_RETURN_uint8_t_array(msg, data, 200,  42);
}

/**
 * @brief Decode a obfuscated_data message into a struct
 *
 * @param msg The message to decode
 * @param obfuscated_data C-struct to decode the message contents into
 */
static inline void mavlink_msg_obfuscated_data_decode(const mavlink_message_t* msg, mavlink_obfuscated_data_t* obfuscated_data)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    obfuscated_data->target_id = mavlink_msg_obfuscated_data_get_target_id(msg);
    obfuscated_data->len = mavlink_msg_obfuscated_data_get_len(msg);
    mavlink_msg_obfuscated_data_get_nonce(msg, obfuscated_data->nonce);
    mavlink_msg_obfuscated_data_get_tag(msg, obfuscated_data->tag);
    mavlink_msg_obfuscated_data_get_data(msg, obfuscated_data->data);
#else
        uint8_t len = msg->len < MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN? msg->len : MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN;
        memset(obfuscated_data, 0, MAVLINK_MSG_ID_OBFUSCATED_DATA_LEN);
    memcpy(obfuscated_data, _MAV_PAYLOAD(msg), len);
#endif
}
