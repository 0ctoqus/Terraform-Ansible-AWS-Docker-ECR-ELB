from flask import request, Flask
import mysql.connector
import json

app = Flask(__name__)

config = {
        'user': 'root',
        'password': 'root',
        'host': 'db',
        'port': '3306',
        'database': 'iktos'
}

@app.route('/')
def index() -> str:
    return json.dumps('We are alive, Hello Iktos !')

@app.route('/api/v1/first_row', methods=['GET'])
def api_row():
    connection = mysql.connector.connect(**config)
    cursor = connection.cursor()
    cursor.execute('SELECT * FROM Adult LIMIT 1')
    result = [elem for elem in cursor]
    cursor.close()
    connection.close()

    return json.dumps(result)

@app.route('/api/v1/mean_value', methods=['GET'])
def api_mean_value():
    if 'column_name' in request.args:
        column_name = request.args['column_name']
    else:
        return "Error: No column_name field provided. Please specify a column_name."

    connection = mysql.connector.connect(**config)
    cursor = connection.cursor()
    cursor.execute('SELECT AVG(' + column_name + ') FROM Adult LIMIT 1')
    results = [elem for elem in cursor]
    cursor.close()
    connection.close()

    return json.dumps({'Mean of ' + column_name: str(results[0][0])})

@app.route('/api/v1/most_frequentvalue', methods=['GET'])
def api_most_frequentvalue():
    if 'column_name' in request.args:
        column_name = request.args['column_name']
    else:
        return "Error: No column_name field provided. Please specify a column_name."

    connection = mysql.connector.connect(**config)
    cursor = connection.cursor()
    cursor.execute(
        'SELECT ' + column_name \
        +  ', COUNT(' + column_name \
        +  ') AS value_occurrence FROM Adult GROUP BY ' \
        + column_name + ' ORDER BY value_occurrence DESC LIMIT 1'
    )
    results = [elem for elem in cursor]
    cursor.close()
    connection.close()

    return json.dumps({'Most frequent value of ' + column_name: str(results[0][0])})

if __name__ == '__main__':
    app.run(host='0.0.0.0')