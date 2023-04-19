// #if OS == .WINDOWS {
//  #load "windows.jai";
// }

#import "Basic"; // For assert
// ofbxlib :: #foreign_library,no_dll "./win/ofbx";

ofbx :: struct {
    Scene :: struct {
        root_element: *Element;
        root : *Root;

        settings: Global_Settings;

        object_map: Table(u64, Object_Pair);

        all_objects: [..]*Object;
        meshes: [..]*Mesh;
        geometries: [..]*Geometry;
        animation_stacks: [..]*Animation_Stack;
        connections: [..]Connection;
        data: [..]u8;
        take_infos: [..]Take_Info;
        videos: [..]Video;
        limb_nodes: [..]*Limb_Node;

        allocator: Allocator;

        frame_rate: float = -1;
    }

    CoordSystem :: enum {
        RightHanded :: 0;
        LeftHanded :: 1;
    }

    Frame_Rate :: enum {
        DEFAULT :: 0;
        _120 :: 1;
        _100 :: 2;
        _60 :: 3;
        _50 :: 4;
        _48 :: 5;
        _30 :: 6;
        _30_DROP :: 7;
        NTSC_DROP_FRAME :: 8;
        NTSC_FULL_FRAME :: 9;
        PAL :: 10;
        CINEMA :: 11;
        _1000 :: 12;
        CINEMA_ND :: 13;
        CUSTOM :: 14;
    }

    UpVector :: enum {
        AxisX :: 0;
        AxisY :: 1;
        AxisZ :: 2;
    }

    Global_Settings :: struct {
        UpAxis:                  UpVector = .AxisX;
        UpAxisSign:              s32 = 1;

        // this seems to be 1-2 in Autodesk (odd/even parity), and 0-2 in Blender (axis as in UpAxis)
        // I recommend to ignore FrontAxis and use just UpVector
        FrontAxis:               s32 = 1;
        FrontAxisSign:           s32 = 1;
        CoordAxis:               CoordSystem = .RightHanded;
        CoordAxisSign:           s32 = 1;
        OriginalUpAxis:          s32 = 0;
        OriginalUpAxisSign:      s32 = 1;
        UnitScaleFactor:         float = 1;
        OriginalUnitScaleFactor: float = 1;
        TimeSpanStart:           float64 = 0;
        TimeSpanStop:            float64 = 0;
        TimeMode:                Frame_Rate = .DEFAULT;
        CustomFrameRate:         float = -1.0;
    }

    Object_Pair :: struct {
        element: *Element;
        object: *Object;
    }

    Take_Info :: struct {
        name:                string;
        filename:            string;
        local_time_from:     float64;
        local_time_to:       float64;
        reference_time_from: float64;
        reference_time_to:   float64;
    }

    get_take_info :: (scene: *Scene, name: string) -> *Take_Info {
        for * scene.take_infos {
            if it.name == name then return it;
        }
        return null;
    }

    Video :: struct {
        filename: string;
        content: string;
        media: string;
    }

    LoadFlags :: enum_flags {
        TRIANGULATE         :: 1;
        IGNORE_GEOMETRY     :: 2;
        IGNORE_BLEND_SHAPES :: 4;
    }

    Connection :: struct {
        type: Connection_Type = .OBJECT_OBJECT;
        from: u64;
        to: u64;
        property: string;

        Connection_Type :: enum {
            OBJECT_OBJECT;
            OBJECT_PROPERTY;
        }
    }

    Object :: struct {
        id: u64;
        name: string;
        element: *Element;
        node_attribute: *Object;
        is_node: bool;
        scene: *Scene;
        type: Object_Type;

        Object_Type :: enum {
            ROOT;
            GEOMETRY;
            SHAPE;
            MATERIAL;
            MESH;
            TEXTURE;
            LIMB_NODE;
            NULL_NODE;
            NODE_ATTRIBUTE;
            CLUSTER;
            SKIN;
            BLEND_SHAPE;
            BLEND_SHAPE_CHANNEL;
            ANIMATION_STACK;
            ANIMATION_LAYER;
            ANIMATION_CURVE;
            ANIMATION_CURVE_NODE;
            POSE;
        }

        make :: (scene: *Scene, element: *Element, type: Object_Type) -> Object {
            obj: Object;
            obj.type = type;
            obj.element = element;
            obj.scene = scene;

            if element.first_property != null && element.first_property.next != null {
                obj.name = to_string(*element.first_property.next.value.data[0]);
            } else {
                obj.name = "\0";
            }
            obj.is_node = false;
            obj.node_attribute = null;
            return obj;
        }

        get_parent :: (object: *Object) -> *Object {
            parent: *Object;
            for connection: object.scene.connections {
                if connection.from == object.id {
                    obj_pair, exists := table_find(*object.scene.object_map, connection.to);
                    if exists && obj_pair.object != null {
                        return obj_pair.object;
                    }
                }
            }
            return null;
        }

        get_global_transform :: (this: *Object) -> Matrix4 {
            parent := Object.get_parent(this);
            if parent == null {
                return eval_local(this, get_local_translation(this), get_local_rotation(this), get_local_scaling(this));
            }

            return get_global_transform(parent) * eval_local(this, get_local_translation(this), get_local_rotation(this), get_local_scaling(this));
        }
    }

    Vector2f64 :: struct {
        x: float64;
        y: float64;
    }

    Vector3f64 :: struct {
        x: float64;
        y: float64;
        z: float64;
    }

    Vector4f64 :: struct {
        x: float64;
        y: float64;
        z: float64;
        w: float64;
    }

    Matrix4f64 :: struct {
        f: [16]float64;
    }

    to_vector2 :: (in: Vector2f64) -> Vector2 {
        v: Vector2;
        v.x = cast(float) in.x;
        v.y = cast(float) in.y;
        return v;
    }

    to_vector3 :: (in: Vector3f64) -> Vector3 {
        v: Vector3;
        v.x = cast(float) in.x;
        v.y = cast(float) in.y;
        v.z = cast(float) in.z;
        return v;
    }

    to_vector4 :: (in: Vector4f64) -> Vector4 {
        v: Vector4;
        v.x = cast(float) in.x;
        v.y = cast(float) in.y;
        v.z = cast(float) in.z;
        v.w = cast(float) in.w;
        return v;
    }

    to_matrix4 :: (in: Matrix4f64) -> Matrix4 {
        m: Matrix4;
        for in.f {
            m.floats[it_index] = cast(float) it;
        }
        return m;
    }

    get_local_translation :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "Lcl Translation", .{});
    }


    get_pre_rotation :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "PreRotation", .{});
    }


    get_local_rotation :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "Lcl Rotation", .{});
    }


    get_local_scaling :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "Lcl Scaling", .{1, 1, 1});
    }

    get_rotation_offset :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "RotationOffset", .{0, 0, 0});
    }

    Rotation_Order :: enum {
        EULER_XYZ;
        EULER_XZY;
        EULER_YZX;
        EULER_YXZ;
        EULER_ZXY;
        EULER_ZYX;
        SPHERIC_XYZ; // Currently unsupported. Treated as EULER_XYZ.
    }

    get_rotation_order :: (obj: *Object) -> Rotation_Order {
        // This assumes that the default rotation order is EULER_XYZ.
        return cast(Rotation_Order) resolve_enum_property(obj, "RotationOrder", cast(int) Rotation_Order.EULER_XYZ);
    }

    get_rotation_pivot :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "RotationPivot", .{0, 0, 0});
    }


    get_post_rotation :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "PostRotation", .{0, 0, 0});
    }


    get_scaling_offset :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "ScalingOffset", .{0, 0, 0});
    }


    get_scaling_pivot :: (obj: *Object) -> Vector3 {
        return resolve_vec3_property(obj, "ScalingPivot", .{0, 0, 0});
    }

    eval_local :: (object: *Object, translation: Vector3, rotation: Vector3, scaling: Vector3) -> Matrix4 {
        rotation_pivot := get_rotation_pivot(object) * RAD_PER_DEG;
        scaling_pivot := get_scaling_pivot(object);
        rotation_order := get_rotation_order(object);

        s := identity_of(Matrix4);
        scale(*s, scaling);

        // t := make_translation_matrix4(translation);;

        r := get_rotation_matrix(rotation, rotation_order);
        r_pre := get_rotation_matrix(get_pre_rotation(object) * RAD_PER_DEG, .EULER_XYZ);
        r_post_inv := get_rotation_matrix(-get_post_rotation(object) * RAD_PER_DEG, .EULER_ZYX);

        r_off   := make_translation_matrix4(get_rotation_offset(object));
        r_p     := make_translation_matrix4(rotation_pivot);
        r_p_inv := make_translation_matrix4(-rotation_pivot);
        s_off   := make_translation_matrix4(get_scaling_offset(object));
        s_p     := make_translation_matrix4(scaling_pivot);
        s_p_inv := make_translation_matrix4(-scaling_pivot);

        // http://help.autodesk.com/view/FBX/2017/ENU/?guid=__files_GUID_10CDD63C_79C1_4F2D_BB28_AD2BE65A02ED_htm
        return r_off * r_p * r_pre * r * r_post_inv * r_p_inv * s_off * s_p * s * s_p_inv;
    }

    get_rotation_matrix :: (euler: Vector3, order: Rotation_Order) -> Matrix4 {
        TO_RAD :: 3.1415926535897932384626433832795028 / 180.0;
        rx := rotation_matrix(Matrix4, from_euler_radians(make_vector3(to_radians(euler.x), 0, 0)));
        ry := rotation_matrix(Matrix4, from_euler_radians(make_vector3(0, to_radians(euler.y), 0)));
        rz := rotation_matrix(Matrix4, from_euler_radians(make_vector3(0, 0, to_radians(euler.z))));
        if order == {
            case .EULER_XYZ; return rz * ry * rx;
            case .EULER_XZY; return ry * rz * rx;
            case .EULER_YXZ; return rz * rx * ry;
            case .EULER_YZX; return rx * rz * ry;
            case .EULER_ZXY; return ry * rx * rz;
            case .EULER_ZYX; return rx * ry * rz;
            case .SPHERIC_XYZ; {
                assert(false);
                return rx * ry * rz;
            }
        }
        return identity_of(Matrix4);
    }


    resolve_vec3_property :: (object: *Object, name: string, default: Vector3) -> Vector3 {
        element := resolve_property(object, name);
        if element == null then return default;
        x := get_property(element, 4);
        if x == null || x.next == null || x.next.next == null then return default;
        return make_vector3(xx Property.to_float64(x), xx Property.to_float64(x.next), xx Property.to_float64(x.next.next));
    }

    resolve_property :: (object: *Object, name: string) -> *Element {
        props := find_child(cast(*Element) object.element, "Properties70");
        if props == null then return null;

        prop := props.child;
        while prop != null {
            if prop.first_property != null && prop.first_property.value == name {
                return prop;
            }
            prop = prop.sibling;
        }
        return null;
    }

    resolve_enum_property :: (object: *Object, name: string, default_value: int) -> int {
        element := resolve_property(object, name);
        if (!element) return default_value;
        x := get_property(element, 4);
        if (!x) return default_value;
        return Property.to_int(x);
    }

    Root :: struct {
        using #as base: Object;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Root {
            root := New(Root, false, allocator);
            root.base = Object.make(scene, element, .ROOT);
            root.is_node = true;
            return root;
        }
    }

    Pose :: struct {
        using #as base: Object;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Pose {
            pose := New(Pose, false, allocator);
            pose.base = Object.make(scene, element, .POSE);
            return pose;
        }

        matrix: Matrix4;
        node: *Object;
        node_id: string;
    }

    Texture :: struct {
        using #as base: Object;

        media: string;
        filename: string;
        relative_filename: string;

        Texture_Type :: enum {
            DIFFUSE;
            NORMAL;
            SPECULAR;
            SHININESS;
            AMBIENT;
            EMISSIVE;
            REFLECTION;
            COUNT;
        }

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Texture {
            texture := New(Texture, false, allocator);
            texture.base = Object.make(scene, element, .TEXTURE);
            return texture;
        }
    }

    Material :: struct {
        using #as base: Object;

        textures: [Texture.Texture_Type.COUNT]*Texture;
        diffuse_color: Vector3;
        specular_color: Vector3;
        reflection_color: Vector3;
        ambient_color: Vector3;
        emissive_color: Vector3;

        diffuse_factor: float64;
        specular_factor: float64;
        reflection_factor: float64;
        shininess: float64;
        shininess_exponent: float64;
        ambient_factor: float64;
        bump_factor: float64;
        emissive_factor: float64;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Material {
            mat := New(Material, false, allocator);
            mat.base = Object.make(scene, element, .MATERIAL);
            return mat;
        }
    }

    Cluster :: struct {
        using #as base: Object;

        link: *Object;
        skin: *Skin;
        indices: [..]s32;
        weights: [..]float64;
        transform_matrix: Matrix4;
        transform_link_matrix: Matrix4;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Cluster {
            cluster := New(Cluster, false, allocator);
            cluster.base = Object.make(scene, element, .CLUSTER);
            cluster.indices.allocator = allocator;
            cluster.weights.allocator = allocator;
            return cluster;
        }

        post_process :: (cluster: *Cluster) -> bool {
            geom := cast(*Geometry) resolve_object_link_reverse(cluster.skin, .GEOMETRY);
            if geom == null then return false;

            ints_tmp: [..]s32;
            ints_tmp.allocator = temp;

            indexes := find_child(cluster.element, "Indexes");
            if indexes != null && indexes.first_property != null {
                if !parse_binary_array(indexes.first_property, *ints_tmp) {
                    return false;
                }
            }

            dbl_tmp: [..]float64;
            dbl_tmp.allocator = temp;

            weights_el := find_child(cluster.element, "Weights");
            if weights_el != null && weights_el.first_property != null {
                if !parse_binary_array(weights_el.first_property, *dbl_tmp) {
                    return false;
                }
            }

            for 0..ints_tmp.count-1 {
                old_idx := ints_tmp[it];
                w := dbl_tmp[it];
                n := *geom.to_new_vertices[old_idx];
                if n.idx == -1 then continue;
                while n != null {
                    array_add(*cluster.indices, cast(s32) n.idx);
                    array_add(*cluster.weights, w);
                    n = n.next;
                }
            }
            return true;
        }
    }

    Skin :: struct {
        using #as base: Object;

        clusters: [..]*Cluster;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Skin {
            skin := New(Skin, false, allocator);
            skin.base = Object.make(scene, element, .SKIN);
            skin.clusters.allocator = allocator;
            return skin;
        }
    }

    Blend_Shape_Channel :: struct {
        using #as base: Object;

        blend_shape: *Blend_Shape;
        deform_percent: float;
        full_weights: [..]float64;
        shapes: [..]*Shape;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Blend_Shape_Channel {
            bsc := New(Blend_Shape_Channel, false, allocator);
            bsc.base = Object.make(scene, element, .BLEND_SHAPE_CHANNEL);
            bsc.full_weights.allocator = allocator;
            bsc.shapes.allocator = allocator;
            return bsc;
        }
    }

    Blend_Shape :: struct {
        using #as base: Object;

        blend_shape_channels: [..]*Blend_Shape_Channel;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Blend_Shape {
            blend_shape := New(Blend_Shape, false, allocator);
            blend_shape.base = Object.make(scene, element, .BLEND_SHAPE);
            blend_shape.blend_shape_channels.allocator = allocator;
            return blend_shape;
        }
    }

    Node_Attribute :: struct {
        using #as base: Object;
        attribute_type: string;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Node_Attribute {
            node_attribute := New(Node_Attribute, false, allocator);
            node_attribute.base = Object.make(scene, element, .NODE_ATTRIBUTE);
            return node_attribute;
        }
    }

    MAX_UVS :: 4;

    Geometry :: struct {
        using #as base: Object;

        vertices: [..]Vector3f64;
        normals: [..]Vector3f64;
        uvs: [MAX_UVS][..]Vector2f64;
        colors: [..]Vector4f64;
        tangents: [..]Vector3f64;
        materials: [..]s32;

        skin: *Skin;
        blend_shape: *Blend_Shape;

        indices: [..]s32;
        to_old_vertices: [..]s32;
        to_new_vertices: [..]New_Vertex;

        Vertex_Data_Mapping :: enum {
            BY_POLYGON_VERTEX;
            BY_POLYGON;
            BY_VERTEX;
        }

        New_Vertex :: struct {
            idx: int = -1;
            next: *New_Vertex;
        }

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Geometry {
            geo := New(Geometry, false, allocator);
            geo.base = Object.make(scene, element, .GEOMETRY);

            geo.vertices.allocator = allocator;
            geo.normals.allocator = allocator;
            geo.uvs[0].allocator = allocator;
            geo.uvs[1].allocator = allocator;
            geo.uvs[2].allocator = allocator;
            geo.uvs[3].allocator = allocator;
            geo.colors.allocator = allocator;
            geo.tangents.allocator = allocator;
            geo.materials.allocator = allocator;
            geo.indices.allocator = allocator;
            geo.to_old_vertices.allocator = allocator;
            geo.to_new_vertices.allocator = allocator;

            return geo;
        }
    }

    Shape :: struct {
        using #as base: Object;

        vertices: [..]Vector3f64;
        normals: [..]Vector3f64;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Shape {
            shape := New(Shape, false, allocator);
            shape.base = Object.make(scene, element, .SHAPE);
            shape.vertices.allocator = allocator;
            shape.normals.allocator = allocator;
            return shape;
        }
    }

    Mesh :: struct {
        using #as base: Object;

        pose: *Pose;
        geometry: *Geometry;
        materials: [..]*Material;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Mesh {
            mesh := New(Mesh, false, allocator);
            mesh.base = Object.make(scene, element, .MESH);
            mesh.is_node = true;
            mesh.materials.allocator = allocator;
            return mesh;
        }

        get_geometric_matrix :: (this: *Mesh) -> Matrix4 {
            translation := resolve_vec3_property(this, "GeometricTranslation", .{0, 0, 0});
            rotation := resolve_vec3_property(this, "GeometricRotation", .{0, 0, 0});
            scale := resolve_vec3_property(this, "GeometricScaling", .{1, 1, 1});

            t := make_translation_matrix4(translation);
            r := get_rotation_matrix(rotation, .EULER_XYZ);
            s := make_scale_matrix4(scale);

            return t * r * s;
        }
    }

    Limb_Node :: struct {
        using #as base: Object;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Limb_Node {
            limb_node := New(Limb_Node, false, allocator);
            limb_node.base = Object.make(scene, element, .LIMB_NODE);
            limb_node.is_node = true;
            return limb_node;
        }
    }

    Null_Node :: struct {
        using #as base: Object;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Null_Node {
            null_node := New(Null_Node, false, allocator);
            null_node.base = Object.make(scene, element, .NULL_NODE);
            null_node.is_node = true;
            return null_node;
        }
    }

    Animation_Stack :: struct {
        using #as base: Object;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Animation_Stack {
            anim_stack := New(Animation_Stack, false, allocator);
            anim_stack.base = Object.make(scene, element, .ANIMATION_STACK);
            return anim_stack;
        }

        get_layer :: (stack: *Animation_Stack, layer: int) -> *Animation_Layer {
            return cast(*ofbx.Animation_Layer) ofbx.resolve_object_link(stack, xx layer);
        }
    }

    Animation_Layer :: struct {
        using #as base: Object;

        curve_nodes: [..]*Animation_Curve_Node;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Animation_Layer {
            anim_layer := New(Animation_Layer, false, allocator);
            anim_layer.base = Object.make(scene, element, .ANIMATION_LAYER);
            anim_layer.curve_nodes.allocator = allocator;
            return anim_layer;
        }

        get_curve_node :: (layer: *Animation_Layer, idx: int) -> *Animation_Curve_Node {
            if idx >= layer.curve_nodes.count || idx < 0 then return null;
            return layer.curve_nodes[idx];
        }

        get_curve_node :: (layer: *Animation_Layer, bone: *Object, prop: string) -> *Animation_Curve_Node {
            for node: layer.curve_nodes {
                if node.bone_link_property == prop && node.bone == bone {
                    return node;
                }
            }

            return null;
        }
    }

    Animation_Curve :: struct {
        using #as base: Object;

        times: []s64;
        values: []float;

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Animation_Curve {
            anim_curve := New(Animation_Curve, false, allocator);
            anim_curve.base = Object.make(scene, element, .ANIMATION_CURVE);
            return anim_curve;
        }
    }

    Animation_Curve_Node :: struct {
        using #as base: Object;

        curves: [3]Curve;
        bone: *Object;
        bone_link_property: string;
        default_values: [3]float;
        mode: Mode = .TRANSLATION;

        Curve :: struct {
            curve: *Animation_Curve;;
            connection: *Connection;
        }

        Mode :: enum {
            TRANSLATION;
            ROTATION;
            SCALE;
        }

        make :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Animation_Curve_Node {
            anim_curve_node := New(Animation_Curve_Node, false, allocator);
            anim_curve_node.base = Object.make(scene, element, .ANIMATION_CURVE_NODE);

            dx := resolve_property(anim_curve_node, "d|X");
            dy := resolve_property(anim_curve_node, "d|Y");
            dz := resolve_property(anim_curve_node, "d|Z");

            if dx != null {
                x := get_property(dx, 4);
                if x != null then anim_curve_node.default_values[0] = cast(float) Property.to_float64(x);
            }

            if dy != null {
                y := get_property(dy, 4);
                if y != null then anim_curve_node.default_values[1] = cast(float) Property.to_float64(y);
            }

            if dz != null {
                z := get_property(dz, 4);
                if z != null then anim_curve_node.default_values[2] = cast(float) Property.to_float64(z);
            }

            return anim_curve_node;
        }

        get_node_local_transform :: (curve: *Animation_Curve_Node, time: float64) -> Vector3 {
            fbx_time := secondsToFbxTime(time);

            get_coord :: (anim_curve: *Animation_Curve_Node, curve: *Curve, fbx_time: s64, idx: int) -> float {
                if curve.curve == null then return anim_curve.default_values[idx];

                times := curve.curve.times;
                values := curve.curve.values;
                count := times.count;

                if fbx_time < times[0] then fbx_time = times[0];
                if fbx_time > times[count - 1] then fbx_time = times[count - 1];

                for 1..count-1 {
                    if fbx_time == times[it] return values[it];

                    if fbx_time < times[it] {
                        a := (cast(float64)fbx_time) / times[it - 1];
                        b := (cast(float64)times[it]) - times[it - 1];
                        t := cast(float) (a / b);
                        return values[it - 1] * (1 - t) + values[it] * t;
                    }
                }
                return 0;
            }

            return make_vector3(get_coord(curve, *curve.curves[0], fbx_time, 0), get_coord(curve, *curve.curves[1], fbx_time, 1), get_coord(curve, *curve.curves[2], fbx_time, 2));
        }
    }

    load :: (data: *u8, size: s32, flags: LoadFlags, allocator: Allocator) -> *Scene {
        scene := New(Scene, true, allocator);

        scene.all_objects.allocator = allocator;
        scene.meshes.allocator = allocator;
        scene.geometries.allocator = allocator;
        scene.animation_stacks.allocator = allocator;
        scene.connections.allocator = allocator;
        scene.data.allocator = allocator;
        scene.take_infos.allocator = allocator;
        scene.videos.allocator = allocator;
        scene.limb_nodes.allocator = allocator;

        {
            PUSH_ALLOCATOR(allocator);
            init(*scene.object_map, 1024);
        }
        scene.object_map.allocator = allocator;

        version: u32;
        is_binary := false;
        if size >= 18 {
            str := to_string(data, 18);
            is_binary = str == "Kaydara FBX Binary";
        }

        root: *Element;
        if is_binary {
            root = tokenize(data, size, *version, allocator);
        } else {
            root = tokenize_text(data, size, allocator);
        }

        assert(root != null);
        scene.root_element = root;

        parse_connections(root, scene);
        parse_takes(scene);
        parse_objects(root, scene, flags, allocator);
        // TODO global settings


        scene.frame_rate = get_framerate_from_time_mode(scene.settings.TimeMode, scene.settings.CustomFrameRate);

        return scene;
    }

    get_framerate_from_time_mode :: (time_mode: Frame_Rate, custom_frame_rate: float) -> float {
        if time_mode == {
            case .DEFAULT; return 14;
            case ._120; return 120;
            case ._100; return 100;
            case ._60; return 60;
            case ._50; return 50;
            case ._48; return 48;
            case ._30; return 30;
            case ._30_DROP; return 30;
            case .NTSC_DROP_FRAME; return 29.97;
            case .NTSC_FULL_FRAME; return 29.97;
            case .PAL; return 25;
            case .CINEMA; return 24;
            case ._1000; return 1000;
            case .CINEMA_ND; return 23.976;
            case .CUSTOM; return custom_frame_rate;
        }
        return -1;
    }

    // Tokenizing

    Header :: struct {
        magic: [21]u8 #align 1;
        reserved: [2]u8 #align 1;
        version: u32 #align 1;
    }

    Property :: struct {
        count: int;
        type: Property_Type;
        value: string;
        next: *Property;
        is_binary: bool = true;

        length: u32;
        encoding: u32;
        compressed_len: u32;

        Property_Type :: enum u8 {
            LONG         :: 76;
            INTEGER      :: 73;
            STRING       :: 83;
            FLOAT        :: 70;
            DOUBLE       :: 68;
            ARRAY_DOUBLE :: 100;
            ARRAY_INT    :: 105;
            ARRAY_LONG   :: 108;
            ARRAY_FLOAT  :: 102;
            BINARY       :: 82;
        }

        to_u64 :: (property: Property) -> u64 {
            if property.is_binary {
                assert(property.value.count == size_of(u64));
                result: u64;
                memcpy(*result, property.value.data, size_of(u64));
                return result;
            }

            res, s, _ := string_to_u64(property.value);
            return xx res;
        }

        to_s64 :: (property: Property) -> s64 {
            if property.is_binary {
                result: s64;
                memcpy(*result, property.value.data, size_of(s64));
                return result;
            }

            res, s, _ := string_to_u64(property.value);
            return xx res;
        }

        to_int :: (property: Property) -> int {
            if property.is_binary {
                result: int;
                memcpy(*result, property.value.data, size_of(int));
                return result;
            }

            res, s, _ := to_integer(property.value);
            return xx res;
        }

        to_u32 :: (property: Property) -> u32 {
            result: u32;
            memcpy(*result, property.value.data, size_of(u32));
            return result;
        }

        to_float64 :: (property: Property) -> float64 {
            if property.is_binary {
                result: float64;
                memcpy(*result, property.value.data, size_of(float64));
                return result;
            }

            res, s, _ := string_to_float64(property.value);
            return res;
        }

        to_float :: (property: Property) -> float {
            if property.is_binary {
                result: float;
                memcpy(*result, property.value.data, size_of(float));
                return result;
            }

            res, s, _ := string_to_float(property.value);
            return res;
        }

        get_count :: (property: Property) -> int {
            assert(property.type == .ARRAY_DOUBLE || property.type == .ARRAY_INT || property.type == .ARRAY_FLOAT || property.type == .ARRAY_LONG);
            if property.is_binary {
                return property.length;
            }
            return property.count;
        }
    }

    parse_array_raw :: (property: *Property, out: *$T, max_size: int) -> bool {
        if property.is_binary {
            elem_size := 1;
            if property.type == {
                case .ARRAY_LONG; elem_size = 8;
                case .ARRAY_DOUBLE; elem_size = 8;
                case .ARRAY_FLOAT; elem_size = 4;
                case .ARRAY_INT; elem_size = 4;
                case; return false;
            }

            data := property.value.data;

            if property.encoding == 0 {
                if property.compressed_len > max_size {
                    log("Array to long for max size. % %\n", max_size, property.compressed_len);
                    return false;
                }

                memcpy(out, data, property.compressed_len);
                return true;
            }

            if property.encoding == 1 {
                if elem_size * property.length > max_size then return false;
                return decompress(data, property.compressed_len, xx out, xx (elem_size * property.length));
            }

            return false;
        }

        return parse_text_array_raw(property, out, max_size);
    }

    parse_binary_array :: (property: *Property, out: *[..]$T) -> bool {
        if property.is_binary {
            elem_size := 1;
            if property.type == {
                case .ARRAY_DOUBLE; elem_size = 8;
                case .ARRAY_FLOAT; elem_size = 4;
                case .ARRAY_INT; elem_size = 4;
                case; return false;
            }
            elem_count := size_of(T) / elem_size;
            array_resize(out, property.length / elem_count);
            if property.length == 0 then return false;
            return parse_array_raw(property, *(<<out)[0], size_of(T) * (<<out).count);
        } else {
            return parse_text_array(property, out);
        }
    }

    parse_double_vec_data :: (property: *Property, out_vec: *[..]$T, tmp: *[..]float) -> bool {
        if !property.is_binary {
            parse_text_array(property, out_vec);
            return true;
        }

        if property.type == .ARRAY_DOUBLE {
            return parse_binary_array(property, out_vec);
        }

        assert(property.type == .ARRAY_FLOAT, "%", property.type);
        // assert(size_of(T[0]) == size_of(float64));

        array_reset_keeping_memory(tmp);

        if !parse_binary_array(property, tmp) return false;

        elem_count := size_of(T) / size_of(float64);
        array_resize(out_vec, tmp.count / elem_count);

        out := cast(*float) out_vec;

        if tmp.count > 0 then for < 0..tmp.count {
            out[it] = (<<tmp)[it];
        }

        return true;
    }

    parse_text_array_raw :: (property: *Property, out_raw: *$T, max_size: int) -> bool {
        d := make_deserializer(property.value);

        out := out_raw;
        while d.cursor < d.buffer.count {
            <<out = read(*d, T);
            out += size_of(T);
            if out - out_raw == max_size / size_of(T) then return true;
        }

        return out - out_raw == max_size / size_of(T);
    }

    parse_text_array :: (property: *Property, out_vec: *[..]$T) -> bool {
        d := make_deserializer(property.value);

        while d.cursor < d.buffer.count {
            array_add(out_vec, read(*d, T));
        }

        return true;
    }

    decompress :: (in: *u8, in_size: u64, out: *u8, out_size: u64) -> bool {
        stream: miniz.mz_stream;
        miniz.mz_inflateInit(*stream);

        stream.avail_in = xx in_size;
        stream.next_in = in;
        stream.avail_out = xx out_size;
        stream.next_out = out;

        status := miniz.mz_inflate(*stream, xx miniz.MZ_2.MZ_SYNC_FLUSH);

        if status != xx miniz.MZ_3.MZ_STREAM_END && status != xx miniz.MZ_3.MZ_OK then return false;

        return miniz.mz_inflateEnd(*stream) == xx miniz.MZ_3.MZ_OK;
    }

    Element :: struct {
        id: string;
        child: *Element;
        sibling: *Element;
        first_property: *Property;

        parent: *Element;
    }

    tokenize :: (data: *u8, size: s32, version: *u32, allocator: Allocator) -> *Element {
        _data: []u8;
        _data.data = data;
        _data.count = size;

        d := make_deserializer(_data);
        header := read(*d, Header);

        <<version = header.version;

        root := New(Element, true, allocator);

        element := *root.child;
        while true {
            child := read_element(*d, header.version, allocator, root);
            if child == null then return root;

            <<element = child;
            element = *child.sibling;
        }
        return null;
    }

    read_element :: (d: *Deserializer, version: u32, allocator: Allocator, parent: *Element = null) -> element: *Element {
        end_offset := read_element_offset(d, version);
        if end_offset == 0 then return null;

        prop_count := read_element_offset(d, version);
        prop_length := read_element_offset(d, version);

        element := New(Element, true, allocator);
        element.id = read_short_string(d, allocator);
        element.parent = parent;

        prop_link := *element.first_property;
        if prop_count > 0 for  0..prop_count-1 {
            p := read_property(d, allocator);

            if p == null {
                return null;
            }

            <<prop_link = p;
            prop_link = *((<<prop_link).next);
        }

        if d.cursor >= cast(int) end_offset return element;

        BLOCK_SENTINEL_LENGTH := 13;
        if version >= 7500 then BLOCK_SENTINEL_LENGTH = 25;

        link := *element.child;
        while cast(u64) d.cursor < end_offset - cast(u64) BLOCK_SENTINEL_LENGTH {
            child := read_element(d, version, allocator, element);

            if child == null then break;

            <<link = child;
            link = *((<<link).sibling);

        }

        advance(d, BLOCK_SENTINEL_LENGTH);
        return element;
    }

    read_element_offset :: (d: *Deserializer, version: u32) -> u64 {
        if version >= 7500 {
            return read(d, u64);
        }

        return cast(u64) read(d, u32);
    }

    read_property :: (d: *Deserializer, allocator: Allocator) -> prop: *Property {
        if d.cursor >= d.buffer.count {
            log("reading past the end\n");
            return null;
        }
        prop := New(Property, true, allocator);
        prop.type = xx read(d, u8);

        if prop.type == {
            case #char "S"; {
                prop.value = read_long_string(d, allocator);
            }
            case #char "Y"; prop.value.data = NewArray(2, u8, false).data; prop.value.count = 2; read(d, u8, *prop.value.data[0], 2);
            case #char "C"; prop.value.data = NewArray(1, u8, false).data; prop.value.count = 1; read(d, u8, *prop.value.data[0], 1);
            case #char "I"; prop.value.data = NewArray(4, u8, false).data; prop.value.count = 4; read(d, u8, *prop.value.data[0], 4);
            case #char "F"; prop.value.data = NewArray(4, u8, false).data; prop.value.count = 4; read(d, u8, *prop.value.data[0], 4);
            case #char "D"; prop.value.data = NewArray(8, u8, false).data; prop.value.count = 8; read(d, u8, *prop.value.data[0], 8);
            case #char "L"; prop.value.data = NewArray(8, u8, false).data; prop.value.count = 8; read(d, u8, *prop.value.data[0], 8);
            case #char "R"; {
                prop.length = read(d, u32);
                prop.value = to_string(read(d, u8, prop.length));
            }
            case #char "b"; #through;
            case #char "f"; #through;
            case #char "d"; #through;
            case #char "l"; #through;
            case #char "i"; {
                prop.length = read(d, u32);
                prop.encoding = read(d, u32);
                prop.compressed_len = read(d, u32);
                prop.value = to_string(read(d, u8, prop.compressed_len));
            }
        }

        return prop;
    }

    read_short_string :: (d: *Deserializer, allocator: Allocator) -> string {
        str: string;
        str.count = xx read(d, u8);
        str.data = new_array(str.count, u8, allocator).data;
        read(d, u8, str.data, str.count);
        return str;
    }

    read_long_string :: (d: *Deserializer, allocator: Allocator) -> string {
        str: string;
        str.count = xx read(d, u32);
        str.data = new_array(str.count, u8, allocator).data;
        read(d, u8, str.data, str.count);
        return str;
    }

    is_end_line :: (d: *Deserializer) -> bool {
        c := peek(d, u8);
        return c == #char "\n" || c == #char "\r" && d.cursor + 1 < d.buffer.count && peek(d, u8, 1) != #char "\n";
    }

    skip_insignificant_whitespace :: (d: *Deserializer) {
        while d.cursor < d.buffer.count && is_space(peek(d, u8)) && !is_end_line(d) {
            advance(d, 1);
        }
    }

    skip_whitespaces :: (d: *Deserializer) {
        while d.cursor < d.buffer.count && is_space(peek(d, u8)) {
            advance(d, 1);
        }

        while d.cursor < d.buffer.count && peek(d, u8) == #char ";" {
            skip_line(d);
        }
    }

    skip_line :: (d: *Deserializer) {
        while d.cursor < d.buffer.count && is_end_line(d) {
            advance(d, 1);
        }

        if d.cursor < d.buffer.count then advance(d, 1);
        skip_insignificant_whitespace(d);
    }

    tokenize_text :: (data: *u8, size: s32, allocator: Allocator) -> *Element {
        root := New(Element, true, allocator);

        element := *root.child;

        _data: []u8;
        _data.data = data;
        _data.count = size;

        d := make_deserializer(_data);

        while d.cursor < d.buffer.count {
            c := peek(*d, u8);
            if c == #char ";" || c == #char "\r" || c == #char "\n" {
                skip_line(*d);
            } else {
                child := read_text_element(*d, allocator);
                if child == null {
                    return null;
                }
                <<element = child;
                if child == null then return root;
                element = *(<<element).sibling;
            }
        }

        return root;
    }

    is_text_token_char :: (d: *Deserializer) -> bool {
        c := read(d, u8);
        return is_alnum(c) || c == #char "_" || c == #char "-";
    }

    read_text_token :: (d: *Deserializer) -> string {
        size := 0;
        while d.cursor < d.buffer.count && is_text_token_char(d) {
            size += 1;
        }

        s: string;
        s.data = *d.buffer[d.cursor - size];
        s.count = size;
        return s;
    }

    read_text_element :: (d: *Deserializer, allocator: Allocator) -> *Element {
        id := read_text_token(d);

        if d.cursor >= d.buffer.count {
            log("Unexpected end of file\n");
            return null;
        }

        if peek(d, u8) != #char ":" {
            log("Unexpected character\n");
            return null;
        }

        advance(d, 1);

        skip_insignificant_whitespace(d);
        if d.cursor >= d.buffer.count {
            log("Unexpected end of file\n");
            return null;
        }

        element := New(Element, true, allocator);
        element.id = id;

        prop_link := *element.first_property;

        while d.cursor < d.buffer.count && !is_end_line(d) && peek(d, u8) != #char "{" {
            prop := read_text_property(d, allocator);
            if prop == null {
                return null;
            }

            if d.cursor < d.buffer.count && peek(d, u8) == #char "," {
                advance(d, 1);
                skip_whitespaces(d);
            }

            skip_insignificant_whitespace(d);

            <<prop_link = prop;
            prop_link = *(<<prop_link).next;
        }

        link := *element.child;
        if peek(d, u8) == #char "{" {
            advance(d, 1);
            skip_whitespaces(d);
            while d.cursor < d.buffer.count && peek(d, u8) != #char "}" {
                child := read_text_element(d, allocator);
                if child == null {
                    return null;
                }

                skip_whitespaces(d);

                <<link = child;
                link = *(<<link).sibling;
            }
        }

        return element;
    }

    read_text_property :: (d: *Deserializer, allocator: Allocator) -> *Property {
        prop := New(Property, true, allocator);
        prop.is_binary = false;

        nc := peek(d, u8);
        if nc == #char "\"" {
            prop.type = .STRING;
            advance(d, 1);

            count := 0;
            while d.cursor < d.buffer.count && peek(d, u8) != #char "\"" {
                count += 1;
            }

            prop.value = to_string(read(d, u8, count));
            advance(d, 1);
        }

        if is_digit(nc) || nc == #char "-" {
            prop.type = .LONG;

            count := 0;
            if nc == #char "-" then count += 1;
            while d.cursor < d.buffer.count && is_digit(peek(d, u8)) {
                count += 1;
            }
            prop.value = to_string(read(d, u8, count));

            if d.cursor < d.buffer.count && peek(d, u8) == #char "." {
                prop.type = .DOUBLE;
                advance(d, 1);

            }
        }

        if nc == #char "T" || nc == #char "Y" || nc == #char "W" || nc == #char "C" {
            // WTF is this
            prop.type = xx nc;
            prop.value = to_string(read(d, u8, 1));
            return prop;
        }

        if nc == #char "*" {
            prop.type = xx #char "l";
            advance(d, 1);

            while d.cursor < d.buffer.count && peek(d, u8) != #char ":" {
                advance(d, 1);
            }

            if d.cursor < d.buffer.count then advance(d, 1);

            skip_insignificant_whitespace(d);

            is_any := false;

            count := 0;
            while d.cursor < d.buffer.count && peek(d, u8) != #char "}" {
                if peek(d, u8) == #char "," {
                    if is_any then prop.count += 1;
                    is_any = false;
                } else if !is_space(peek(d, u8)) && !is_end_line(d) {
                    is_any = true;
                }

                if peek(d, u8) == #char "." then prop.type = xx #char "d";
                count += 1;
            }

            if is_any then prop.count += 1;
            prop.value = to_string(read(d, u8, count));
            return prop;
        }

        return null;;
    }


    // Parsing
    parse_connections :: (root: *Element, scene: *Scene) -> bool {
        connections := find_child(root, "Connections");
        if connections == null then return true;

        connection := connections.child;
        while connection != null {
            if connection.first_property.type != .STRING ||
               connection.first_property.next.type != .LONG ||
               connection.first_property.next.next.type != .LONG {
                log("Invalid Connection\n");
                return false;
            }

            c: Connection;
            c.from = Property.to_u64(connection.first_property.next);
            c.to = Property.to_u64(connection.first_property.next.next);

            if connection.first_property.value == "OO" {
                c.type = .OBJECT_OBJECT;
            } else if connection.first_property.value == "OP" {
                c.type = .OBJECT_PROPERTY;

                if connection.first_property.next.next.next == null {
                    log("Invalid Connection\n");
                    return false;
                }

                c.property = to_string(*connection.first_property.next.next.next.value.data[0]);
            } else {
                log("Unsuported\n");
                return false;
            }

            array_add(*scene.connections, c);
            connection = connection.sibling;
        }

        return true;
    }

    fbxTimeToSeconds :: (value: s64) -> float64
    {
        return cast(float64)value / 46186158000;
    }


    secondsToFbxTime :: (value: float64) -> s64
    {
        return cast(s64) (value * 46186158000);
    }

    parse_takes :: (scene: *Scene) -> bool {
        takes := find_child(scene.root_element, "Takes");
        if takes == null then return false;

        object := takes.child;
        while object != null {
            if object.id == "Take" {
                if object.first_property.type != .STRING {
                    log("Invalid name in take\n");
                    return false;
                }

                take: Take_Info;
                take.name = to_string(*object.first_property.value.data[0]);

                filename := find_child(object, "FileName");
                if filename != null {
                    if filename.first_property.type != .STRING {
                        log("Invalid file name in take\n");
                        return false;
                    }
                    take.filename = filename.first_property.value;
                }

                local_time := find_child(object, "LocalTime");
                if local_time != null {
                    if local_time.first_property.type != .LONG ||
                       local_time.first_property.next.type != .LONG {
                        log("Invalid local time in take\n");
                        return false;
                    }
                    take.local_time_from = fbxTimeToSeconds(Property.to_s64(local_time.first_property));
                    take.local_time_to = fbxTimeToSeconds(Property.to_s64(local_time.first_property.next));
                }

                reference_time := find_child(object, "ReferenceTime");
                if reference_time != null {
                    if reference_time.first_property.type != .LONG ||
                       reference_time.first_property.next.type != .LONG {
                        log("Invalid reference time in take\n");
                        return false;
                    }
                    take.reference_time_from = fbxTimeToSeconds(Property.to_s64(reference_time.first_property));
                    take.reference_time_to = fbxTimeToSeconds(Property.to_s64(reference_time.first_property.next));
                }

                array_add(*scene.take_infos, take);
            }
            object = object.sibling;
        }
        return true;
    }

    parse_objects :: (root: *Element, scene: *Scene, flags: LoadFlags, allocator: Allocator) -> bool {
        triangulate := flags & .TRIANGULATE != 0;
        ignore_geo := flags & .IGNORE_GEOMETRY != 0;
        ignore_blend_shapes := flags & .IGNORE_BLEND_SHAPES != 0;

        objs := find_child(root, "Objects");

        scene.root = Root.make(scene, root, allocator);
        scene.root.id = 0;

        root_pair: Object_Pair;
        root_pair.element = root;
        root_pair.object = scene.root;

        table_add(*scene.object_map, 0, root_pair);

        object := objs.child;
        while object != null {
            if object.first_property.type != .LONG {
                log("Invalid\n");
                return false;
            }

            id := Property.to_u64(object.first_property);

            object_pair: Object_Pair;
            object_pair.element = object;

            table_add(*scene.object_map, id, object_pair);
            object = object.sibling;
        }

        for * scene.object_map {
            obj: *Object;

            if it.object == scene.root then continue;

            if it.element.id == {
                case "Geometry"; {
                    last_prop := it.element.first_property;
                    while last_prop.next != null { last_prop = last_prop.next; }

                    if last_prop != null && last_prop.value == "Mesh" && !ignore_geo {
                        geo := parse_geometry(scene, it.element, triangulate, allocator);
                        array_add(*scene.geometries, geo);
                        obj = geo;
                    }

                    if last_prop != null && last_prop.value == "Shape" && !ignore_geo {
                        obj = Shape.make(scene, it.element, allocator);
                    }
                }

                case "Material"; {
                    obj = parse_material(scene, it.element, allocator);
                }

                case "AnimationStack"; {
                    obj = Animation_Stack.make(scene, it.element, allocator);
                    array_add(*scene.animation_stacks, cast(*Animation_Stack) obj);
                }

                case "AnimationLayer"; {
                    obj = Animation_Layer.make(scene, it.element, allocator);
                }

                case "AnimationCurve"; {
                    obj = parse_animation_curve(scene, it.element, allocator);
                }

                case "AnimationCurveNode"; {
                    obj = Animation_Curve_Node.make(scene, it.element, allocator);
                }

                case "Deformer"; {
                    class_prop := get_property(it.element, 2);
                    if class_prop != null {
                        if class_prop.value == {
                            case "Cluster"; obj = parse_cluster(scene, it.element, allocator);
                            case "Skin";    obj = Skin.make(scene, it.element, allocator);
                            case "BlendShape";        if !ignore_blend_shapes then Blend_Shape.make(scene, it.element, allocator);
                            case "BlendShapeChannel"; if !ignore_blend_shapes then Blend_Shape_Channel.make(scene, it.element, allocator);
                        }
                    }
                }

                case "NodeAttribute"; {
                    obj = Node_Attribute.make(scene, it.element, allocator);
                }

                case "Model"; {
                    class_prop := get_property(it.element, 2);
                    if class_prop != null {
                        if class_prop.value == "Mesh" {
                            obj = parse_mesh(scene, it.element, allocator);
                            array_add(*scene.meshes, cast(*Mesh) obj);
                        } else if class_prop.value == "LimbNode" {
                            obj = parse_limb_node(scene, it.element, allocator);
                            array_add(*scene.limb_nodes, cast(*Limb_Node) obj);
                        } else {
                            obj = Null_Node.make(scene, it.element, allocator);
                        }
                    }
                }

                case "Texture"; {
                    obj = parse_texture(scene, it.element, allocator);
                }

                case "Video"; {
                    parse_video(scene, it.element, allocator);
                }

                case "Pose"; {
                    obj = parse_pose(scene, it.element, allocator);
                }
            }

            if obj == null {
                continue;
            }

            obj.id = it_index;
            it.object = obj;
            array_add(*scene.all_objects, obj);
        }

        for * con: scene.connections {
            parent_op := table_find_pointer(*scene.object_map, con.to);
            child_op := table_find_pointer(*scene.object_map, con.from);

            if parent_op == null {
                // log("Failed to find connection parent: %\n", con.to);
                continue;
            }

            if child_op == null {
                // log("Failed to find connection child: %\n", con.from);
                continue;
            }

            parent := parent_op.object;
            child := child_op.object;

            if child == null || parent == null then continue;

            if child.type == {
                case .NODE_ATTRIBUTE; {
                    parent.node_attribute = cast(*Node_Attribute) child;
                }
                case .ANIMATION_CURVE_NODE; {
                    if parent.is_node {
                        node := cast(*Animation_Curve_Node)child;
                        node.bone = parent;
                        node.bone_link_property = con.property;
                    }
                }
            }

            if parent.type == {
                case .MESH; {
                    mesh := cast(*Mesh)parent;
                    if child.type == {
                        case .GEOMETRY; {
                            mesh.geometry = cast(*Geometry)child;
                        }
                        case .MATERIAL; {
                            array_add(*mesh.materials, cast(*Material)child);
                        }
                    }
                }
                case .SKIN; {
                    skin := cast(*Skin)parent;
                    if child.type == .CLUSTER {
                        cluster := cast(*Cluster)child;
                        array_add(*skin.clusters, cluster);
                        cluster.skin = skin;
                    }
                }
                case .BLEND_SHAPE; {
                    blend_shape := cast(*Blend_Shape) parent;
                    if child.type == .BLEND_SHAPE_CHANNEL {
                        bsc := cast(*Blend_Shape_Channel)child;
                        array_add(*blend_shape.blend_shape_channels, bsc);
                        bsc.blend_shape = blend_shape;
                    }
                }
                case .BLEND_SHAPE_CHANNEL; {
                    bsc := cast(*Blend_Shape_Channel) parent;
                    if child.type == .SHAPE {
                        array_add(*bsc.shapes, cast(*Shape) child);
                    }
                }
                case .MATERIAL; {
                    mat := cast(*Material) parent;
                    if child.type == .TEXTURE {
                        type := Texture.Texture_Type.COUNT;
                        if con.property == {
                            case "NormalMap";         type = .NORMAL;
                            case "DiffuseColor";      type = .DIFFUSE;
                            case "SpecularColor";     type = .SPECULAR;
                            case "ShininessExponent"; type = .SHININESS;
                            case "EmissiveColor";     type = .EMISSIVE;
                            case "AmbientColor";      type = .AMBIENT;
                            case "ReflectionFactor";  type = .REFLECTION;
                        }

                        if type != .COUNT && mat.textures[cast(int) type] == null {
                            mat.textures[cast(int) type] = cast(*Texture) child;
                        }
                    }
                }
                case .GEOMETRY; {
                    geom := cast(*Geometry) parent;
                    if child.type == .SKIN {
                        geom.skin = cast(*Skin) child;
                    }
                    if child.type == .BLEND_SHAPE {
                        geom.blend_shape = cast(*Blend_Shape)child;
                    }
                }
                case .CLUSTER; {
                    cluster := cast(*Cluster) parent;
                    if child.type == .LIMB_NODE || child.type == .MESH || child.type == .NULL_NODE {
                        cluster.link = child;
                    }
                }
                case .ANIMATION_LAYER; {
                    if child.type == .ANIMATION_CURVE_NODE {
                        anim_layer := cast(*Animation_Layer)parent;
                        array_add(*anim_layer.curve_nodes, cast(*Animation_Curve_Node) child);
                    }
                }
                case .ANIMATION_CURVE_NODE; {
                    node := cast(*Animation_Curve_Node) parent;
                    if child.type == .ANIMATION_CURVE {
                        if con.property == "d|X" {
                            node.curves[0].connection = con;
                            node.curves[0].curve = cast(*Animation_Curve) child;
                        }

                        if con.property == "d|Y" {
                            node.curves[1].connection = con;
                            node.curves[1].curve = cast(*Animation_Curve) child;
                        }

                        if con.property == "d|Z" {
                            node.curves[2].connection = con;
                            node.curves[2].curve = cast(*Animation_Curve) child;
                        }
                    }
                }
            }
        }

        if !ignore_geo {
            for scene.object_map {
                if it.object == null then continue;

                if it.object.type == {
                    case .CLUSTER; {
                        if !Cluster.post_process(cast(*Cluster)it.object) {
                            log("Failed to post process cluster");
                            return false;
                        }
                    }
                }
            }
        }

        return true;
    }

    Temporaries :: struct {
        f: [..]float;
        i: [..]s32;
        v2: [..]Vector2f64;
        v3: [..]Vector3f64;
        v4: [..]Vector4f64;
    }

    get_tri_count_from_poly :: (indices: *[..]s32, idx: *int) -> int {
        count := 1;
        while (<<indices)[<<idx + 1 + count] >= 0 {
            count += 1;
        }

        <<idx = <<idx + 2 + count;
        return count;
    }

    decode_index :: (idx: s32) -> s32 {
        if idx < 0 then return -idx - 1;
        return idx;
    }


    code_index :: (idx: s32, last: bool) -> s32 {
        if last then return -idx - 1;
        return idx;
    }

    splat :: (out: *[..]$T, mapping: Geometry.Vertex_Data_Mapping, data: *[..]T, indices: *[..]s32, original_indicies: *[..]s32) {
        assert(out != null);
        assert(data.count != 0);

        if mapping == {
            case .BY_POLYGON_VERTEX; {
                if indices.count == 0 {
                    array_resize(out, data.count);
                    memcpy(*out.data[0], *(<<data)[0], size_of(T) * data.count);
                } else {
                    array_resize(out, indices.count);
                    for 0..indices.count-1 {
                        idx := (<<indices)[it];
                        if idx < data.count && idx >= 0 {
                            (<<out)[it] = (<<data)[idx];
                        }
                    }
                }
            }
            case .BY_VERTEX; {
                assert(indices.count == 0);
                array_resize(out, original_indicies.count);

                for 0..original_indicies.count-1 {
                    idx := decode_index((<<original_indicies)[it]);
                    if idx < data.count && idx >= 0 {
                        (<<out)[it] = (<<data)[idx];
                    }
                }
            }
            case; {
                assert(false);
            }
        }
    }

    remap :: (out: *[..]$T, map: *[..]s32) {
        if out.count == 0 then return;

        old := array_copy(<<out);
        array_reset_keeping_memory(out);

        if map.count > 0 then for 0..map.count-1 {
            if (<<map)[it] < old.count {
                array_add(out, old[(<<map)[it]]);
            } else {
                _ := array_add(out);
            }
        }

    }

    parse_vertex_data :: (element: *Element, name: string, index_name: string, out: *[..]$T, out_indices: *[..]s32, mapping: *Geometry.Vertex_Data_Mapping, tmp: *[..]float) -> bool {
        assert(out != null);
        assert(mapping != null);

        data_element := find_child(element, name);
        if data_element == null || data_element.first_property == null {
            return false;
        }


        array_reset_keeping_memory(out_indices);

        mapping_element := find_child(element, "MappingInformationType");
        if mapping_element != null && mapping_element.first_property != null {
            mapping_type := to_string(*mapping_element.first_property.value.data[0]);
            if mapping_type == {
                case "ByPolygonVertex"; {
                    <<mapping = .BY_POLYGON_VERTEX;
                }
                case "ByPolygon"; {
                    <<mapping = .BY_POLYGON;
                }
                case "ByVertice"; #through;
                case "ByVertex"; {
                    <<mapping = .BY_VERTEX;
                }
                case; return false;
            }
        }

        reference_element := find_child(element, "ReferenceInformationType");
        if reference_element != null && reference_element.first_property != null {
            reference_type := to_string(*reference_element.first_property.value.data[0]);
            if reference_type == "IndexToDirect" {
                indices_element := find_child(element, index_name);
                if indices_element != null && indices_element.first_property != null {
                    if !parse_binary_array(indices_element.first_property, out_indices) {
                        return false;
                    }
                }
            } else if reference_type != "Direct" {
                return false;
            }
        }

        return parse_double_vec_data(data_element.first_property, out, tmp);
    }

    parse_geometry_materials :: (geom: *Geometry, element: *Element, original_indicies: *[..]s32, to_old_indicies: *[..]s32, tmp: *Temporaries) -> bool {
        layer_material_element := find_child(element, "LayerElementMaterial");
        if layer_material_element == null then return true;

        mapping_element := find_child(layer_material_element,"MappingInformationType");
        reference_element := find_child(layer_material_element, "ReferenceInformationType");

        if mapping_element == null || reference_element == null {
            log("Invalid LayerElementMaterial\n");
            return false;
        }

        if mapping_element.first_property.value == "ByPolygon" && reference_element.first_property.value == "IndexToDirect" {
            indices_element := find_child(layer_material_element, "Materials");
            if indices_element == null || indices_element.first_property == null {
                log("Invalid LayerElementMaterial\n");
                return false;
            }

            tmp: [..]s32;
            tmp.allocator = temp;

            if !parse_binary_array(indices_element.first_property, *tmp) {
                log("failed to parse material indices\n");
                return false;
            }

            tmp_i := 0;
            for < poly: 0..tmp.count {
                tri_count := get_tri_count_from_poly(original_indicies, *tmp_i);
                if tri_count > 0 then for < 0..tri_count {
                    array_add(*geom.materials, tmp[poly]);
                }
            }
        } else {
            if mapping_element.first_property.value != "AllSame" {
                log("Mapping not supported\n");
                return false;
            }
        }

        return true;
    }

    parse_geometry_uvs :: (geom: *Geometry, element: *Element, original_indicies: *[..]s32, to_old_indicies: *[..]s32, tmp: *Temporaries) -> bool {
        layer_uv_element := find_child(element, "LayerElementUV");
        while layer_uv_element != null {
            uv_idx := ifx layer_uv_element.first_property != null then Property.to_int(layer_uv_element.first_property) else 0;
            if uv_idx >= 0 && uv_idx < MAX_UVS {
                uvs := *geom.uvs[uv_idx];

                array_reset_keeping_memory(*tmp.v2);
                array_reset_keeping_memory(*tmp.i);

                mapping: Geometry.Vertex_Data_Mapping;
                if !parse_vertex_data(layer_uv_element, "UV", "UVIndex", *tmp.v2, *tmp.i, *mapping, *tmp.f) {
                    log("Invalid UVs\n");
                    return false;
                }

                if tmp.v2.count != 0 && (tmp.i.count == 0 || tmp.i[0] != -1) {
                    array_resize(uvs, ifx tmp.i.count == 0 then tmp.v2.count else tmp.i.count);
                    splat(uvs, mapping, *tmp.v2, *tmp.i, original_indicies);
                    remap(uvs, to_old_indicies);
                }
            }

            layer_uv_element = layer_uv_element.sibling;
            while layer_uv_element && layer_uv_element.id != "LayerElementUV" {
                layer_uv_element = layer_uv_element.sibling;
            }
        }
        return true;
    }

    parse_geometry_tangents :: (geom: *Geometry, element: *Element, original_indicies: *[..]s32, to_old_indicies: *[..]s32, tmp: *Temporaries) -> bool {
        layer_tangent_element := find_child(element, "LayerElementTangets");
        if layer_tangent_element == null {
            layer_tangent_element = find_child(element, "LayerElementTanget");
        }

        if layer_tangent_element != null {
            mapping: Geometry.Vertex_Data_Mapping;
            if find_child(layer_tangent_element, "Tangents") == null {
                if !parse_vertex_data(layer_tangent_element, "Tangents", "TangentsIndex", *tmp.v3, *tmp.i, *mapping, *tmp.f) {
                    log("Invalid tangents\n");
                    return false;
                }
            } else {
                if !parse_vertex_data(layer_tangent_element, "Tangents", "TangentIndex", *tmp.v3, *tmp.i, *mapping, *tmp.f) {
                    log("Invalid tangents\n");
                    return false;
                }
            }

            if tmp.v3.count != 0 {
                splat(*geom.tangents, mapping, *tmp.v3, *tmp.i, original_indicies);
                remap(*geom.tangents, to_old_indicies);
            }
        }
        return true;
    }

    parse_geometry_colors :: (geom: *Geometry, element: *Element, original_indicies: *[..]s32, to_old_indicies: *[..]s32, tmp: *Temporaries) -> bool {
        layer_color_element := find_child(element, "LayerElementColor");
        if layer_color_element != null {
            mapping: Geometry.Vertex_Data_Mapping;
            if !parse_vertex_data(layer_color_element, "Colors", "ColorIndex", *tmp.v4, *tmp.i, *mapping, *tmp.f) {
                log("Invalid Colors\n");
                return false;
            }
            if tmp.v4.count != 0 {
                splat(*geom.colors, mapping, *tmp.v4, *tmp.i, original_indicies);
                remap(*geom.colors, to_old_indicies);
            }
        }
        return true;
    }

    parse_geometry_normals :: (geom: *Geometry, element: *Element, original_indicies: *[..]s32, to_old_indicies: *[..]s32, tmp: *Temporaries) -> bool {
        layer_normal_element := find_child(element, "LayerElementNormal");
        if layer_normal_element != null {
            mapping: Geometry.Vertex_Data_Mapping;
            if !parse_vertex_data(layer_normal_element, "Normals", "NormalsIndex", *tmp.v3, *tmp.i, *mapping, *tmp.f) {
                log("Invalid Normals\n");
                return false;
            }
            if tmp.v3.count != 0 {
                splat(*geom.normals, mapping, *tmp.v3, *tmp.i, original_indicies);
                remap(*geom.normals, to_old_indicies);
            }
        }
        return true;
    }

    triangulate :: (old_indicies: *[..]s32, to_old_vertices: *[..]s32, to_old_indicies: *[..]s32) {
        in_polygon_idx := 0;
        for <<old_indicies {
            idx := decode_index(it);
            if in_polygon_idx <= 2 {
                array_add(to_old_vertices, idx);
                array_add(to_old_indicies, cast(s32) it_index);
            } else {
                array_add(to_old_vertices, (<<old_indicies)[it_index - in_polygon_idx]);
                array_add(to_old_indicies, cast(s32)  (it_index - in_polygon_idx));
                array_add(to_old_vertices, (<<old_indicies)[it_index - 1]);
                array_add(to_old_indicies, cast(s32)  (it_index - 1));
                array_add(to_old_vertices, idx);
                array_add(to_old_indicies, cast(s32)  it_index);
            }
            in_polygon_idx += 1;
            if it < 0 {
                in_polygon_idx = 0;
            }
        }
    }

    add :: (vtx: *Geometry.New_Vertex, index: int, allocator: Allocator) {
        if vtx.idx == -1 {
            vtx.idx = index;
        } else if vtx.next {
            add(vtx.next, index, allocator);
        } else {
            vtx.next = New(Geometry.New_Vertex, true, allocator);
            vtx.next.idx = index;
        }
    }

    build_geometry_vertex_data :: (geom: *Geometry, vertices: *[..]Vector3f64, original_indicies: *[..]s32, to_old_indicies: *[..]s32, tri: bool, allocator: Allocator) {
        if tri {
            triangulate(original_indicies, *geom.to_old_vertices, to_old_indicies);

            for geom.to_old_vertices {
                array_add(*geom.vertices, (<<vertices)[it]);
                array_add(*geom.indices, xx code_index(cast(s32) it_index, it_index % 3 == 2)); //;
            }
        } else {
            geom.vertices = <<vertices;
            array_reset_keeping_memory(*geom.to_old_vertices);
            if geom.to_old_vertices.count > 0 then for 0..geom.to_old_vertices.count-1 {
                array_add(*geom.to_old_vertices, decode_index((<<original_indicies)[it]));
            }
            geom.indices = <<original_indicies;
            array_resize(to_old_indicies, original_indicies.count);

            iota : s32 = 0;
            if original_indicies.count > 0 then for 0..original_indicies.count-1 {
                (<<to_old_indicies)[it] = iota;
                iota += 1;
            }
        }

        array_resize(*geom.to_new_vertices, geom.to_old_vertices.count);
        for geom.to_old_vertices {
            add(*geom.to_new_vertices[it], it_index, allocator);
        }
    }

    parse_geometry :: (scene: *Scene, element: *Element, triangulate: bool, allocator: Allocator) -> *Geometry {
        geo := Geometry.make(scene, element, allocator);

        vertices_element := find_child(element, "Vertices");
        if vertices_element == null || vertices_element.first_property == null {
            return geo;
        }

        polys_element := find_child(element, "PolygonVertexIndex");
        if polys_element == null || polys_element.first_property == null {
            return geo;
        }

        vertices: [..]Vector3f64;
        original_indicies: [..]s32;
        to_old_indicies: [..]s32;
        temp: Temporaries;

        if !parse_double_vec_data(vertices_element.first_property, *vertices, *temp.f) {
            log("Failed to parse vertices\n");
            return geo;
        }

        if !parse_binary_array(polys_element.first_property, *original_indicies) {
            log("Failed to parse indices\n");
            return geo;
        }

        build_geometry_vertex_data(geo, *vertices, *original_indicies, *to_old_indicies, triangulate, allocator);

        if !parse_geometry_materials(geo, element, *original_indicies, *to_old_indicies, *temp) {
            log("Failed to parse geometry materials\n");
            return geo;
        }

        if !parse_geometry_uvs(geo, element, *original_indicies, *to_old_indicies, *temp) {
            log("failed to parse_geometry_uvs\n");
            return geo;
        }

        if !parse_geometry_tangents(geo, element, *original_indicies, *to_old_indicies, *temp) {
            log("failed to parse_geometry_tangents\n");
            return geo;
        }

        if !parse_geometry_colors(geo, element, *original_indicies, *to_old_indicies, *temp) {
            log("failed to parse_geometry_colors\n");
            return geo;
        }

        if !parse_geometry_normals(geo, element, *original_indicies, *to_old_indicies, *temp) {
            log("failed to parse_geometry_normals\n");
            return geo;
        }

        return geo;
    }

    parse_material :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Material {
        material := Material.make(scene, element, allocator);

        prop := find_child(element, "Properties70");
        material.diffuse_color = .{1,1,1};
        if prop != null {
            prop = prop.child;
        }

        while prop != null {
            if prop.id == "P" && prop.first_property != null {
                if prop.first_property.value == {
                    case "DiffuseColour"; {
                        material.diffuse_color.x = cast(float) Property.to_float64(get_property(prop, 4));
                        material.diffuse_color.y = cast(float) Property.to_float64(get_property(prop, 5));
                        material.diffuse_color.z = cast(float) Property.to_float64(get_property(prop, 6));
                    }
                    case "SpecularColor"; {
                        material.specular_color.x = cast(float) Property.to_float64(get_property(prop, 4));
                        material.specular_color.y = cast(float) Property.to_float64(get_property(prop, 5));
                        material.specular_color.z = cast(float) Property.to_float64(get_property(prop, 6));
                    }
                    case "Shininess"; {
                        material.shininess = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                    case "ShininessExponent"; {
                        material.shininess_exponent = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                    case "ReflectionColor"; {
                        material.reflection_color.x = cast(float) Property.to_float64(get_property(prop, 4));
                        material.reflection_color.y = cast(float) Property.to_float64(get_property(prop, 5));
                        material.reflection_color.z = cast(float) Property.to_float64(get_property(prop, 6));
                    }
                    case "AmbientColor"; {
                        material.ambient_color.x = cast(float) Property.to_float64(get_property(prop, 4));
                        material.ambient_color.y = cast(float) Property.to_float64(get_property(prop, 5));
                        material.ambient_color.z = cast(float) Property.to_float64(get_property(prop, 6));
                    }
                    case "EmissiveColor"; {
                        material.emissive_color.x = cast(float) Property.to_float64(get_property(prop, 4));
                        material.emissive_color.y = cast(float) Property.to_float64(get_property(prop, 5));
                        material.emissive_color.z = cast(float) Property.to_float64(get_property(prop, 6));
                    }
                    case "ReflectionFactor"; {
                        material.reflection_factor = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                    case "BumpFactor"; {
                        material.bump_factor = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                    case "AmbientFactor"; {
                        material.ambient_factor = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                    case "DiffuseFactor"; {
                        material.diffuse_factor = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                    case "SpecularFactor"; {
                        material.specular_factor = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                    case "EmissiveFactor"; {
                        material.emissive_factor = cast(float) Property.to_float64(get_property(prop, 4));
                    }
                }
            }

            prop = prop.sibling;
        }

        return material;
    }

    parse_animation_curve :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Animation_Curve {
        anim_curve := Animation_Curve.make(scene, element, allocator);

        id := Property.to_u64(element.first_property);

        times := find_child(element, "KeyTime");
        values := find_child(element, "KeyValueFloat");

        if times != null && times.first_property != null {
            anim_curve.times = NewArray(times.first_property.length, s64, false, allocator);
            if !parse_array_raw(times.first_property, *anim_curve.times.data[0], anim_curve.times.count * size_of(s64)) {
                log("Invalid Animation Curve. %\n", #line);
                return null;
            }
        }

        if values != null && values.first_property != null {
            anim_curve.values = NewArray(values.first_property.length, float, false, allocator);
            if !parse_array_raw(values.first_property, *anim_curve.values.data[0], anim_curve.values.count * size_of(float)) {
                log("Invalid Animation Curve. %\n", #line);
                return null;
            }
        }

        if anim_curve.times.count != anim_curve.values.count {
            log("Times, and Values mismatch. %\n", #line);
        }

        return anim_curve;
    }

    parse_cluster :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Cluster {
        cluster := Cluster.make(scene, element, allocator);

        transform_link := find_child(element, "TransformLink");
        if transform_link != null && transform_link.first_property != null {
            m4: Matrix4f64;
            if !parse_array_raw(transform_link.first_property, *m4, size_of(Matrix4f64)) {
                log("Failed to parse TransformLink. %\n", #line);
            }
            cluster.transform_link_matrix = to_matrix4(m4);
        }

        transform := find_child(element, "Transform");
        if transform != null && transform.first_property != null {
            m4: Matrix4f64;
            if !parse_array_raw(transform.first_property, *m4, size_of(Matrix4f64)) {
                log("Failed to parse transform. %\n", #line);
            }
            cluster.transform_matrix = to_matrix4(m4);
        }

        return cluster;
    }

    parse_node_attribute :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Node_Attribute {
        node_attribute := Node_Attribute.make(scene, element, allocator);

        type_flags := find_child(element, "TypeFlags");
        if type_flags != null && type_flags.first_property != null {
            node_attribute.attribute_type = type_flags.first_property.value;
        }

        return node_attribute;
    }

    parse_mesh :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Mesh {
        mesh := Mesh.make(scene, element, allocator);
        return mesh;
    }

    parse_limb_node :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Limb_Node {
        limb_node := Limb_Node.make(scene, element, allocator);
        return limb_node;
    }

    parse_texture :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Texture {
        texture := Texture.make(scene, element, allocator);

        filename := find_child(element, "FileName");
        if filename != null && filename.first_property != null {
            texture.filename = filename.first_property.value;
        }

        media := find_child(element, "Media");
        if media != null && media.first_property != null {
            texture.media = media.first_property.value;
        }

        relative_filename := find_child(element, "RelativeFilename");
        if relative_filename != null && relative_filename.first_property != null {
            texture.relative_filename = relative_filename.first_property.value;
        }

        return texture;
    }

    parse_video :: (scene: *Scene, element: *Element, allocator: Allocator) -> Video {
        return .{};
    }

    parse_pose :: (scene: *Scene, element: *Element, allocator: Allocator) -> *Pose {
        pose := Pose.make(scene, element, allocator);

        pose_node := find_child(element, "PoseNode");
        if pose_node != null {
            node := find_child(pose_node, "Node");
            matrix := find_child(pose_node, "Matrix");

            if matrix.first_property != null {
                m4: Matrix4f64;
                parse_array_raw(matrix.first_property, *m4, size_of(Matrix4f64));
                pose.matrix = to_matrix4(m4);
            }

            pose.node_id = node.first_property.value;
        }

        return pose;
    }

    parse_global_settings :: (root: *Element, scene: *Scene) -> Global_Settings {
        global_settings: Global_Settings;

        return global_settings;
    }

    get_property :: (element: *Element, idx: int) -> *Property {
        prop := element.first_property;
        assert(idx >= 0);
        for 0..idx-1 {
            if prop == null return null;
            prop = prop.next;
        }
        return prop;
    }

    find_child :: (element: *Element, id: string) -> *Element {
        iter := *element.child;
        while <<iter != null {
            if (<<iter).id == id then return <<iter;
            iter = *((<<iter).sibling);
        }

        return null;
    }

    resolve_object_link :: (obj: *Object, idx: u64) -> *Object {
        id := Property.to_u64(obj.element.first_property);
        for con: obj.scene.connections {
            if con.to == id && con.from != 0 {
                o := table_find_pointer(*obj.scene.object_map, con.from).object;
                if o {
                    if idx == 0 then return o;
                    idx -= 1;
                }
            }
        }
        return null;
    }

    resolve_object_link_reverse :: (obj: *Object, type: Object.Object_Type) -> *Object {
        scene := obj.scene;

        id : u64 = 0;
        if obj.element.first_property != null {
            id = Property.to_u64(obj.element.first_property);
        }

        for scene.connections {
            if it.from == id && it.to != 0 {
                pair, exists := table_find(*scene.object_map, it.to);
                if exists && pair.object != null && pair.object.type == type {
                    return pair.object;
                }
            }
        }

        return null;
    }
}