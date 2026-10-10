// Run: firebase emulators:exec --project demo-cgid-comments --only firestore "node tool/test-reading-comment-rules.cjs"
// All fixtures are local; refuse to contact production.
const assert = require('node:assert/strict');
const project = 'demo-cgid-comments';
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host || !/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw Error('Local Firestore emulator required');
const root = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const name = `projects/${project}/databases/(default)/documents`;
const target = 'faith_' + 'a'.repeat(64);
const collection = `reading_comments/${target}/comments`;
const fields = values => Object.fromEntries(Object.entries(values).map(([key, value]) => [key,
  typeof value === 'boolean' ? {booleanValue: value} : {stringValue: value}]));
const token = (uid, verified = true) => {
  const now = Math.floor(Date.now()/1000);
  return Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url') + '.' + Buffer.from(JSON.stringify({sub:uid,user_id:uid,aud:project,iss:`https://securetoken.google.com/${project}`,iat:now,exp:now+3600,email:`${uid}@example.org`,email_verified:verified,firebase:{sign_in_provider:'password'}})).toString('base64url') + '.';
};
async function api(path, method, data, user) {
  const response = await fetch(root + path, {method, headers:{'Content-Type':'application/json', ...(user ? {Authorization:'Bearer '+user} : {})}, body:data === undefined ? undefined : JSON.stringify(data)});
  return {status:response.status, body:await response.json()};
}
let checks = 0;
async function expect(label, expected, promise) {
  const result = await promise;
  assert.equal(result.status, expected, `${label}: ${JSON.stringify(result.body)}`);
  checks++;
  console.log('PASS ' + label);
}
const comment = (authorId='pastor-a', churchId='church-a', visible=true, authorRole='pastor') => ({body:'Comentario de prueba',visible,churchId,authorId,authorRole,targetType:'faith',targetLabel:'Punto de fe'});
function create(id, data, user) {
  return api(':commit','POST',{writes:[{update:{name:`${name}/${collection}/${id}`,fields:fields(data)},currentDocument:{exists:false},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]},user);
}
function update(id, data, user) {
  return api(':commit','POST',{writes:[{update:{name:`${name}/${collection}/${id}`,fields:fields(data)},updateMask:{fieldPaths:Object.keys(data)},currentDocument:{exists:true},updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]},user);
}
function query(filters, user) {
  const clauses = Object.entries(filters).map(([key,value]) => ({fieldFilter:{field:{fieldPath:key},op:'EQUAL',value:typeof value==='boolean'?{booleanValue:value}:{stringValue:value}}}));
  return api(`/reading_comments/${target}:runQuery`,'POST',{structuredQuery:{from:[{collectionId:'comments'}],...(clauses.length?{where:clauses.length===1?clauses[0]:{compositeFilter:{op:'AND',filters:clauses}}}:{})}},user);
}
(async()=>{
  for (const [uid,role,churchId] of [['admin','admin','church-a'],['pastor-a','pastor','church-a'],['pastor-b','pastor','church-b'],['collaborator','colaborador','church-a'],['musician','musico','church-a']]) {
    await expect('seed '+uid,200,api('/users/'+uid,'PATCH',{fields:fields({email:`${uid}@example.org`,role,churchId})},'owner'));
  }
  await expect('pastor publishes own church',200,create('public',comment(),token('pastor-a')));
  await expect('pastor saves hidden draft',200,create('hidden',comment('pastor-a','church-a',false),token('pastor-a')));
  await expect('guest reads published comment',200,api('/'+collection+'/public','GET'));
  await expect('guest cannot read hidden comment',403,api('/'+collection+'/hidden','GET'));
  await expect('another pastor cannot read hidden comment',403,api('/'+collection+'/hidden','GET',undefined,token('pastor-b')));
  await expect('author reads own draft',200,api('/'+collection+'/hidden','GET',undefined,token('pastor-a')));
  await expect('administrator reads draft',200,api('/'+collection+'/hidden','GET',undefined,token('admin')));
  await expect('guest public query',200,query({visible:true}));
  await expect('guest unfiltered query rejected',403,query({}));
  await expect('pastor own church management query',200,query({authorId:'pastor-a',churchId:'church-a'},token('pastor-a')));
  await expect('admin all-comments query',200,query({},token('admin')));
  for (const uid of ['collaborator','musician']) await expect(uid+' cannot publish',403,create(uid,comment(uid),token(uid)));
  await expect('guest cannot publish',403,create('guest',comment()));
  await expect('unverified cannot publish',403,create('unverified',comment(),token('pastor-a',false)));
  await expect('pastor cannot impersonate author',403,create('impersonate',comment('pastor-b'),token('pastor-a')));
  await expect('pastor cannot assign another church',403,create('wrong-church',comment('pastor-a','church-b'),token('pastor-a')));
  await expect('pastor cannot claim administrator',403,create('wrong-role',comment('pastor-a','church-a',true,'admin'),token('pastor-a')));
  await expect('empty body rejected',403,create('empty',{...comment(),body:''},token('pastor-a')));
  await expect('oversize body rejected',403,create('large',{...comment(),body:'x'.repeat(3001)},token('pastor-a')));
  await expect('unexpected fields rejected',403,create('extra',{...comment(),state:'fake'},token('pastor-a')));
  await expect('admin can publish nationally',200,create('national',comment('admin','',true,'admin'),token('admin')));
  await expect('pastor cannot edit another author',403,update('national',{body:'changed'},token('pastor-a')));
  await expect('owner can edit',200,update('public',{body:'Updated'},token('pastor-a')));
  await expect('owner cannot change attribution',403,update('public',{authorId:'pastor-b'},token('pastor-a')));
  await expect('owner cannot change church',403,update('public',{churchId:'church-b'},token('pastor-a')));
  await expect('admin can hide any comment',200,update('public',{visible:false},token('admin')));
  await expect('hidden comment immediately denied to guest',403,api('/'+collection+'/public','GET'));
  await expect('admin can republish',200,update('public',{visible:true},token('admin')));
  console.log(`${checks} security checks passed.`);
})().catch(error=>{console.error(error);process.exit(1);});
