from RedisArray import RedisArray
import redis


def main():
    r = redis.Redis(host='localhost', port=6379, db=0)
    arr = RedisArray(r, b'computer', length=4096)



if __name__ == "__main__":
    main()
