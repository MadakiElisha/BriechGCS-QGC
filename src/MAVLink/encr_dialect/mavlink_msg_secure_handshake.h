#pragma once
// MESSAGE SECURE_HANDSHAKE PACKING

#define MAVLINK_MSG_ID_SECURE_HANDSHAKE 11000


typedef struct __mavlink_secure_handshake_t {
 uint8_t target_system; /*<  System ID*/
 uint8_t nonce[24]; /*<  Nonce*/
 uint8_t state; /*<  Handshake State (0: Init, 1: Ack, 2: Final, 3: Error)*/
 uint8_t key[32]; /*<  Curve 25519 Public Key or Verification Key*/
 uint8_t tag[16]; /*<  Auth tag for ChaCha20*/
} mavlink_secure_handshake_t;

#define MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN 74
#define MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN 74
#define MAVLINK_MSG_ID_11000_LEN 74
#define MAVLINK_MSG_ID_11000_MIN_LEN 74

#define MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC 124
#define MAVLINK_MSG_ID_11000_CRC 124

#define MAVLINK_MSG_SECURE_HANDSHAKE_FIELD_NONCE_LEN 24
#define MAVLINK_MSG_SECURE_HANDSHAKE_FIELD_KEY_LEN 32
#define MAVLINK_MSG_SECURE_HANDSHAKE_FIELD_TAG_LEN 16

#if MAVLINK_COMMAND_24BIT
#define MAVLINK_MESSAGE_INFO_SECURE_HANDSHAKE { \
    11000, \
    "SECURE_HANDSHAKE", \
    5, \
    {  { "target_system", NULL, MAVLINK_TYPE_UINT8_T, 0, 0, offsetof(mavlink_secure_handshake_t, target_system) }, \
         { "nonce", NULL, MAVLINK_TYPE_UINT8_T, 24, 1, offsetof(mavlink_secure_handshake_t, nonce) }, \
         { "state", NULL, MAVLINK_TYPE_UINT8_T, 0, 25, offsetof(mavlink_secure_handshake_t, state) }, \
         { "key", NULL, MAVLINK_TYPE_UINT8_T, 32, 26, offsetof(mavlink_secure_handshake_t, key) }, \
         { "tag", NULL, MAVLINK_TYPE_UINT8_T, 16, 58, offsetof(mavlink_secure_handshake_t, tag) }, \
         } \
}
#else
#define MAVLINK_MESSAGE_INFO_SECURE_HANDSHAKE { \
    "SECURE_HANDSHAKE", \
    5, \
    {  { "target_system", NULL, MAVLINK_TYPE_UINT8_T, 0, 0, offsetof(mavlink_secure_handshake_t, target_system) }, \
         { "nonce", NULL, MAVLINK_TYPE_UINT8_T, 24, 1, offsetof(mavlink_secure_handshake_t, nonce) }, \
         { "state", NULL, MAVLINK_TYPE_UINT8_T, 0, 25, offsetof(mavlink_secure_handshake_t, state) }, \
         { "key", NULL, MAVLINK_TYPE_UINT8_T, 32, 26, offsetof(mavlink_secure_handshake_t, key) }, \
         { "tag", NULL, MAVLINK_TYPE_UINT8_T, 16, 58, offsetof(mavlink_secure_handshake_t, tag) }, \
         } \
}
#endif

/**
 * @brief Pack a secure_handshake message
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param msg The MAVLink message to compress the data into
 *
 * @param target_system  System ID
 * @param nonce  Nonce
 * @param state  Handshake State (0: Init, 1: Ack, 2: Final, 3: Error)
 * @param key  Curve 25519 Public Key or Verification Key
 * @param tag  Auth tag for ChaCha20
 * @return length of the message in bytes (excluding serial stream start sign)
 */
static inline uint16_t mavlink_msg_secure_handshake_pack(uint8_t system_id, uint8_t component_id, mavlink_message_t* msg,
                               uint8_t target_system, const uint8_t *nonce, uint8_t state, const uint8_t *key, const uint8_t *tag)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN];
    _mav_put_uint8_t(buf, 0, target_system);
    _mav_put_uint8_t(buf, 25, state);
    _mav_put_uint8_t_array(buf, 1, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, key, 32);
    _mav_put_uint8_t_array(buf, 58, tag, 16);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), buf, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
#else
    mavlink_secure_handshake_t packet;
    packet.target_system = target_system;
    packet.state = state;
    mav_array_assign_uint8_t(packet.nonce, nonce, 24);
    mav_array_assign_uint8_t(packet.key, key, 32);
    mav_array_assign_uint8_t(packet.tag, tag, 16);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), &packet, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
#endif

    msg->msgid = MAVLINK_MSG_ID_SECURE_HANDSHAKE;
    return mavlink_finalize_message(msg, system_id, component_id, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
}

/**
 * @brief Pack a secure_handshake message
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param status MAVLink status structure
 * @param msg The MAVLink message to compress the data into
 *
 * @param target_system  System ID
 * @param nonce  Nonce
 * @param state  Handshake State (0: Init, 1: Ack, 2: Final, 3: Error)
 * @param key  Curve 25519 Public Key or Verification Key
 * @param tag  Auth tag for ChaCha20
 * @return length of the message in bytes (excluding serial stream start sign)
 */
static inline uint16_t mavlink_msg_secure_handshake_pack_status(uint8_t system_id, uint8_t component_id, mavlink_status_t *_status, mavlink_message_t* msg,
                               uint8_t target_system, const uint8_t *nonce, uint8_t state, const uint8_t *key, const uint8_t *tag)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN];
    _mav_put_uint8_t(buf, 0, target_system);
    _mav_put_uint8_t(buf, 25, state);
    _mav_put_uint8_t_array(buf, 1, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, key, 32);
    _mav_put_uint8_t_array(buf, 58, tag, 16);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), buf, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
#else
    mavlink_secure_handshake_t packet;
    packet.target_system = target_system;
    packet.state = state;
    mav_array_memcpy(packet.nonce, nonce, sizeof(uint8_t)*24);
    mav_array_memcpy(packet.key, key, sizeof(uint8_t)*32);
    mav_array_memcpy(packet.tag, tag, sizeof(uint8_t)*16);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), &packet, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
#endif

    msg->msgid = MAVLINK_MSG_ID_SECURE_HANDSHAKE;
#if MAVLINK_CRC_EXTRA
    return mavlink_finalize_message_buffer(msg, system_id, component_id, _status, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
#else
    return mavlink_finalize_message_buffer(msg, system_id, component_id, _status, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
#endif
}

/**
 * @brief Pack a secure_handshake message on a channel
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param chan The MAVLink channel this message will be sent over
 * @param msg The MAVLink message to compress the data into
 * @param target_system  System ID
 * @param nonce  Nonce
 * @param state  Handshake State (0: Init, 1: Ack, 2: Final, 3: Error)
 * @param key  Curve 25519 Public Key or Verification Key
 * @param tag  Auth tag for ChaCha20
 * @return length of the message in bytes (excluding serial stream start sign)
 */
static inline uint16_t mavlink_msg_secure_handshake_pack_chan(uint8_t system_id, uint8_t component_id, uint8_t chan,
                               mavlink_message_t* msg,
                                   uint8_t target_system,const uint8_t *nonce,uint8_t state,const uint8_t *key,const uint8_t *tag)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN];
    _mav_put_uint8_t(buf, 0, target_system);
    _mav_put_uint8_t(buf, 25, state);
    _mav_put_uint8_t_array(buf, 1, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, key, 32);
    _mav_put_uint8_t_array(buf, 58, tag, 16);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), buf, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
#else
    mavlink_secure_handshake_t packet;
    packet.target_system = target_system;
    packet.state = state;
    mav_array_assign_uint8_t(packet.nonce, nonce, 24);
    mav_array_assign_uint8_t(packet.key, key, 32);
    mav_array_assign_uint8_t(packet.tag, tag, 16);
        memcpy(_MAV_PAYLOAD_NON_CONST(msg), &packet, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
#endif

    msg->msgid = MAVLINK_MSG_ID_SECURE_HANDSHAKE;
    return mavlink_finalize_message_chan(msg, system_id, component_id, chan, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
}

/**
 * @brief Encode a secure_handshake struct
 *
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param msg The MAVLink message to compress the data into
 * @param secure_handshake C-struct to read the message contents from
 */
static inline uint16_t mavlink_msg_secure_handshake_encode(uint8_t system_id, uint8_t component_id, mavlink_message_t* msg, const mavlink_secure_handshake_t* secure_handshake)
{
    return mavlink_msg_secure_handshake_pack(system_id, component_id, msg, secure_handshake->target_system, secure_handshake->nonce, secure_handshake->state, secure_handshake->key, secure_handshake->tag);
}

/**
 * @brief Encode a secure_handshake struct on a channel
 *
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param chan The MAVLink channel this message will be sent over
 * @param msg The MAVLink message to compress the data into
 * @param secure_handshake C-struct to read the message contents from
 */
static inline uint16_t mavlink_msg_secure_handshake_encode_chan(uint8_t system_id, uint8_t component_id, uint8_t chan, mavlink_message_t* msg, const mavlink_secure_handshake_t* secure_handshake)
{
    return mavlink_msg_secure_handshake_pack_chan(system_id, component_id, chan, msg, secure_handshake->target_system, secure_handshake->nonce, secure_handshake->state, secure_handshake->key, secure_handshake->tag);
}

/**
 * @brief Encode a secure_handshake struct with provided status structure
 *
 * @param system_id ID of this system
 * @param component_id ID of this component (e.g. 200 for IMU)
 * @param status MAVLink status structure
 * @param msg The MAVLink message to compress the data into
 * @param secure_handshake C-struct to read the message contents from
 */
static inline uint16_t mavlink_msg_secure_handshake_encode_status(uint8_t system_id, uint8_t component_id, mavlink_status_t* _status, mavlink_message_t* msg, const mavlink_secure_handshake_t* secure_handshake)
{
    return mavlink_msg_secure_handshake_pack_status(system_id, component_id, _status, msg,  secure_handshake->target_system, secure_handshake->nonce, secure_handshake->state, secure_handshake->key, secure_handshake->tag);
}

/**
 * @brief Send a secure_handshake message
 * @param chan MAVLink channel to send the message
 *
 * @param target_system  System ID
 * @param nonce  Nonce
 * @param state  Handshake State (0: Init, 1: Ack, 2: Final, 3: Error)
 * @param key  Curve 25519 Public Key or Verification Key
 * @param tag  Auth tag for ChaCha20
 */
#ifdef MAVLINK_USE_CONVENIENCE_FUNCTIONS

static inline void mavlink_msg_secure_handshake_send(mavlink_channel_t chan, uint8_t target_system, const uint8_t *nonce, uint8_t state, const uint8_t *key, const uint8_t *tag)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char buf[MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN];
    _mav_put_uint8_t(buf, 0, target_system);
    _mav_put_uint8_t(buf, 25, state);
    _mav_put_uint8_t_array(buf, 1, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, key, 32);
    _mav_put_uint8_t_array(buf, 58, tag, 16);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_SECURE_HANDSHAKE, buf, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
#else
    mavlink_secure_handshake_t packet;
    packet.target_system = target_system;
    packet.state = state;
    mav_array_assign_uint8_t(packet.nonce, nonce, 24);
    mav_array_assign_uint8_t(packet.key, key, 32);
    mav_array_assign_uint8_t(packet.tag, tag, 16);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_SECURE_HANDSHAKE, (const char *)&packet, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
#endif
}

/**
 * @brief Send a secure_handshake message
 * @param chan MAVLink channel to send the message
 * @param struct The MAVLink struct to serialize
 */
static inline void mavlink_msg_secure_handshake_send_struct(mavlink_channel_t chan, const mavlink_secure_handshake_t* secure_handshake)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    mavlink_msg_secure_handshake_send(chan, secure_handshake->target_system, secure_handshake->nonce, secure_handshake->state, secure_handshake->key, secure_handshake->tag);
#else
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_SECURE_HANDSHAKE, (const char *)secure_handshake, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
#endif
}

#if MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN <= MAVLINK_MAX_PAYLOAD_LEN
/*
  This variant of _send() can be used to save stack space by reusing
  memory from the receive buffer.  The caller provides a
  mavlink_message_t which is the size of a full mavlink message. This
  is usually the receive buffer for the channel, and allows a reply to an
  incoming message with minimum stack space usage.
 */
static inline void mavlink_msg_secure_handshake_send_buf(mavlink_message_t *msgbuf, mavlink_channel_t chan,  uint8_t target_system, const uint8_t *nonce, uint8_t state, const uint8_t *key, const uint8_t *tag)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    char *buf = (char *)msgbuf;
    _mav_put_uint8_t(buf, 0, target_system);
    _mav_put_uint8_t(buf, 25, state);
    _mav_put_uint8_t_array(buf, 1, nonce, 24);
    _mav_put_uint8_t_array(buf, 26, key, 32);
    _mav_put_uint8_t_array(buf, 58, tag, 16);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_SECURE_HANDSHAKE, buf, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
#else
    mavlink_secure_handshake_t *packet = (mavlink_secure_handshake_t *)msgbuf;
    packet->target_system = target_system;
    packet->state = state;
    mav_array_assign_uint8_t(packet->nonce, nonce, 24);
    mav_array_assign_uint8_t(packet->key, key, 32);
    mav_array_assign_uint8_t(packet->tag, tag, 16);
    _mav_finalize_message_chan_send(chan, MAVLINK_MSG_ID_SECURE_HANDSHAKE, (const char *)packet, MAVLINK_MSG_ID_SECURE_HANDSHAKE_MIN_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN, MAVLINK_MSG_ID_SECURE_HANDSHAKE_CRC);
#endif
}
#endif

#endif

// MESSAGE SECURE_HANDSHAKE UNPACKING


/**
 * @brief Get field target_system from secure_handshake message
 *
 * @return  System ID
 */
static inline uint8_t mavlink_msg_secure_handshake_get_target_system(const mavlink_message_t* msg)
{
    return _MAV_RETURN_uint8_t(msg,  0);
}

/**
 * @brief Get field nonce from secure_handshake message
 *
 * @return  Nonce
 */
static inline uint16_t mavlink_msg_secure_handshake_get_nonce(const mavlink_message_t* msg, uint8_t *nonce)
{
    return _MAV_RETURN_uint8_t_array(msg, nonce, 24,  1);
}

/**
 * @brief Get field state from secure_handshake message
 *
 * @return  Handshake State (0: Init, 1: Ack, 2: Final, 3: Error)
 */
static inline uint8_t mavlink_msg_secure_handshake_get_state(const mavlink_message_t* msg)
{
    return _MAV_RETURN_uint8_t(msg,  25);
}

/**
 * @brief Get field key from secure_handshake message
 *
 * @return  Curve 25519 Public Key or Verification Key
 */
static inline uint16_t mavlink_msg_secure_handshake_get_key(const mavlink_message_t* msg, uint8_t *key)
{
    return _MAV_RETURN_uint8_t_array(msg, key, 32,  26);
}

/**
 * @brief Get field tag from secure_handshake message
 *
 * @return  Auth tag for ChaCha20
 */
static inline uint16_t mavlink_msg_secure_handshake_get_tag(const mavlink_message_t* msg, uint8_t *tag)
{
    return _MAV_RETURN_uint8_t_array(msg, tag, 16,  58);
}

/**
 * @brief Decode a secure_handshake message into a struct
 *
 * @param msg The message to decode
 * @param secure_handshake C-struct to decode the message contents into
 */
static inline void mavlink_msg_secure_handshake_decode(const mavlink_message_t* msg, mavlink_secure_handshake_t* secure_handshake)
{
#if MAVLINK_NEED_BYTE_SWAP || !MAVLINK_ALIGNED_FIELDS
    secure_handshake->target_system = mavlink_msg_secure_handshake_get_target_system(msg);
    mavlink_msg_secure_handshake_get_nonce(msg, secure_handshake->nonce);
    secure_handshake->state = mavlink_msg_secure_handshake_get_state(msg);
    mavlink_msg_secure_handshake_get_key(msg, secure_handshake->key);
    mavlink_msg_secure_handshake_get_tag(msg, secure_handshake->tag);
#else
        uint8_t len = msg->len < MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN? msg->len : MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN;
        memset(secure_handshake, 0, MAVLINK_MSG_ID_SECURE_HANDSHAKE_LEN);
    memcpy(secure_handshake, _MAV_PAYLOAD(msg), len);
#endif
}
