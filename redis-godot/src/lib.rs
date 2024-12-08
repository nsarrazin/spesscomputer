use godot::prelude::*;
use redis::Commands;
use lazy_static::lazy_static;
use r2d2::{Pool, PooledConnection};
struct MyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}

lazy_static! {
    static ref REDIS_POOL: Pool<redis::Client> = {
        let client = redis::Client::open("redis://127.0.0.1/").unwrap();
        r2d2::Pool::builder().build(client).unwrap()
    };
}

pub fn get_redis_conn() -> PooledConnection<redis::Client> {
    REDIS_POOL.get().unwrap()
}


#[derive(GodotClass)]
#[class(no_init)] // We only provide a custom constructor.
struct RedisArray {
    key: String,
    #[allow(dead_code)]
    #[var(get = get_field, set = set_field)]
    values: Array<u8>,
}

#[godot_api]
impl RedisArray {
    #[func]
    pub fn create(key: String) -> Gd<Self> {
        Gd::from_object(Self {
            key,
            values: Array::new(),
        })
    }

    #[func]
    pub fn get_field(&self) -> Array<u8> {
        let mut conn = get_redis_conn();
        let data: Vec<u8> = conn.get(&self.key).unwrap_or_default();
        let mut array = Array::new();
        for byte in data {
            array.push(byte);
        }
        array
    }

    #[func]
    pub fn set_field_byte(&mut self, index: i32, value: u8) {
        let mut conn = get_redis_conn();
        conn.setrange(&self.key, index as isize, &[value]).unwrap_or(());
    }

    #[func]
    pub fn set_field(&mut self, values: Array<u8>) {
        let mut conn = get_redis_conn();
        let mut bytes = Vec::new();
        for i in 0..values.len() {
            if let Some(byte) = values.get(i as usize) {
                bytes.push(byte);
            }
        }
        conn.set(&self.key, bytes).unwrap_or(());
    }
}

impl Drop for RedisArray {
    fn drop(&mut self) {
        godot_print!("RedisArray '{}' is being destroyed!", self.key);
        let mut conn = get_redis_conn();
        conn.del(&self.key).unwrap_or(());
        godot_print!("RedisArray '{}' deleted!", self.key);
    }
}