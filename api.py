from flask import Flask

from flask_sqlalchemy import SQLAlchemy

from flask_restful import Resource ,Api ,reqparse,fields,marshal_with,abort
from dotenv import load_dotenv
import os
# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ['DATABASE_URI']  
api=Api(app)
db=SQLAlchemy(app)

class UserModel(db.Model):
    id = db.Column(db.Integer,primary_key=True)
    name= db.Column(db.String(80),unique=True,nullable=False)
    email = db.Column(db.String(80),unique=True,nullable=False)
    
    def __repr__(self):
        return f"User(name = {self.name},email={self.email})"
    
user_args = reqparse.RequestParser()
user_args.add_argument('name',type=str, required=True,help="Name cannot be blank")    
user_args.add_argument('email',type=str, required=True,help="Name cannot be blank")    

userFields={
    'id':fields.Integer,
    'name':fields.String,
    'email':fields.String,
}
class Users(Resource):
    @marshal_with(userFields)
    def get(self):
        users = UserModel.query.all()
        return users  
    @marshal_with(userFields)
    def post(self):
        args=user_args.parse_args()
        user=UserModel(name=args["name"],email=args["email"])
        db.session.add(user)
        db.session.commit()
        users=UserModel.query.all()
        return users ,201

class User(Resource):
    @marshal_with(userFields)
    def get(self,id):
        user =UserModel.query.filter_by(id=id).first()
        if not user:
            abort(404)
        return user
        
    @marshal_with(userFields)
    def patch (self , id ):
        args = user_args.parse_args()
        user =UserModel.query.filter_by(id=id).first()
        if not user:
            abort(404)
        user.name = args["name"]
        user.email= args["email"]   
        db.session.commit()    
        return user
    
    @marshal_with(userFields)
    def delete (self , id ):
        user =UserModel.query.filter_by(id=id).first()
        if not user:
            abort(404)
        db.session.delete(user)
        db.session.commit()
        users=UserModel.query.all()
        return users ,204

    
api.add_resource(Users,'/api/user/')
api.add_resource(User,'/api/user/<int:id>')



   
@app.route('/')
def home():
    
    return '<h1> FLASK REST API </h1>'

if __name__ == '__main__':  
    with app.app_context():
        db.create_all()
    app.run(host='0.0.0.0', port=5000)
