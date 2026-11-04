import pytest

from coordinator.config import Config, ConfigError


def test_defaults():
    cfg = Config.from_env({})
    assert cfg.mqtt_port == 8883 and cfg.http_port == 8443 and cfg.mqtt_tls
    assert cfg.operator_tokens == frozenset() and not cfg.tls_enabled


def test_secrets_from_files(tmp_path):
    (tmp_path / "pw").write_text("s3cret\n")
    (tmp_path / "ops").write_text("tok-a\ntok-b\n")
    (tmp_path / "dev").write_text("# devices\ntower-01=dt1\nedge-02=dt2\n")
    cfg = Config.from_env({
        "BRIECH_MQTT_PASSWORD_FILE": str(tmp_path / "pw"),
        "BRIECH_OPERATOR_TOKENS_FILE": str(tmp_path / "ops"),
        "BRIECH_DEVICE_TOKENS_FILE": str(tmp_path / "dev"),
    })
    assert cfg.mqtt_password == "s3cret"
    assert cfg.operator_tokens == {"tok-a", "tok-b"}
    assert cfg.device_tokens == {"dt1": "tower-01", "dt2": "edge-02"}


def test_direct_value_wins_over_file(tmp_path):
    (tmp_path / "pw").write_text("from-file")
    cfg = Config.from_env({"BRIECH_MQTT_PASSWORD": "direct", "BRIECH_MQTT_PASSWORD_FILE": str(tmp_path / "pw")})
    assert cfg.mqtt_password == "direct"


def test_errors(tmp_path):
    with pytest.raises(ConfigError):
        Config.from_env({"BRIECH_TLS_CERT": "cert.pem"})
    with pytest.raises(ConfigError):
        Config.from_env({"BRIECH_DEVICE_TOKENS": "no-equals-sign"})
    with pytest.raises(ConfigError):
        Config.from_env({"BRIECH_MQTT_PASSWORD_FILE": str(tmp_path / "missing")})
    with pytest.raises(ConfigError):
        Config.from_env({"BRIECH_CLIENT_QUEUE_SIZE": "0"})


def test_plain_mqtt_for_tests():
    assert not Config.from_env({"BRIECH_MQTT_TLS": "false"}).mqtt_tls
