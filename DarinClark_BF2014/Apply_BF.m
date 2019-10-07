%% Filter MRI data

preview_slice = 69;
At = single([1]);
sz = [200 280 128];
sz = int32(sz);
w = 6;
w2 = 0.8;
m = single(2);
A_ = make_A_approx_3D_v2( w, w2 );
A_ = single(A_);
w = int32(w);
nvols = int32(3);
ntimes = int32(1);

% Load data
X = zeros(prod(sz),3,'single');

temp = load_nii('H:\AlexBadea\M1_RIGID_ADC.hdr');
temp = temp.img;
X(:,1) = temp(:);

temp = load_nii('H:\AlexBadea\M1_RIGID_dw');
temp = temp.img;
X(:,2) = temp(:);

temp = load_nii('H:\AlexBadea\M1_RIGID_fa.hdr');
temp = temp.img;
X(:,3) = temp(:);

d = X*0;
v = X*0;
X_out = X;
lambda = 3;

for kreg = 1:5

    [d,~,flag] = jointBF4D(X_out+v,nvols,ntimes,A_,At,sz,w,m);
    
    v = X_out + v - d;
    
    X_out = (X + lambda*(d-v))/(1+lambda);

end

x_slices = reshape(X,[sz(1) sz(2) sz(3) 3]);
x_slices = reshape(x_slices(:,:,preview_slice,:),[sz(1) sz(2) 3]);

x_out_slices = reshape(X_out,[sz(1) sz(2) sz(3) 3]);
x_out_slices = reshape(x_out_slices(:,:,preview_slice,:),[sz(1) sz(2) 3]);

imtool(mat2gray([x_slices(:,:,1) x_out_slices(:,:,1) 4*abs(x_slices(:,:,1)-x_out_slices(:,:,1))]));
imtool(mat2gray([x_slices(:,:,2) x_out_slices(:,:,2) 4*abs(x_slices(:,:,2)-x_out_slices(:,:,2))]));
imtool(mat2gray([x_slices(:,:,3) x_out_slices(:,:,3) 4*abs(x_slices(:,:,3)-x_out_slices(:,:,3))]));

% save_nii(make_nii(reshape(X_out,[sz(1) sz(2) sz(3) 3]),[1 1 1],[0 0 0],16),'H:\AlexBadea\Smoothed.nii');
save_nii(make_nii(reshape(X_out(:,1),[sz(1) sz(2) sz(3)]),[1 1 1],[0 0 0],16),'H:\AlexBadea\ADC_Smoothed.nii');
save_nii(make_nii(reshape(X_out(:,2),[sz(1) sz(2) sz(3)]),[1 1 1],[0 0 0],16),'H:\AlexBadea\dw_Smoothed.nii');
save_nii(make_nii(reshape(X_out(:,3),[sz(1) sz(2) sz(3)]),[1 1 1],[0 0 0],16),'H:\AlexBadea\fa_Smoothed.nii');